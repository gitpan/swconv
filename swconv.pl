#!/usr/bin/perl -w

# $Id: swconv.pl,v 1.13 1998/09/25 04:14:53 jzawodn Exp $

# Script to help out with shared-web migration at Marathon/MAP.

# See the manual/documentation for details...

use strict;                             # enable warnings and stuff
use Getopt::Long;                       # cmd-line options
use File::stat;                         # for file information
use File::Copy;                         # for file copies
use File::Find;                         # for directory recursion

# Global variables, command-line options, and friends.

my $debug              = 0;             # debugging
my $test               = 0;             # running in test mode?
my $backup             = 1;             # make backups of changed files?
my $no_backup          = 0;             # used to get above value
my $verbose            = 0;             # print messages?
my $help               = 0;             # trigger help message
my $logfile            = "";            # where to log
my $old_url_prefix     = "";            # the original url prefix
my $new_url_prefix     = "";            # the new url prefix
my $dir_is_source      = 0;             #
my $dir_is_destination = 0;             #
my $total_changes      = 0;             # count changes
my $total_files_changed= 0;             # count files changed
my $total_files_seen   = 0;             # count files seen

# Process command-line options.


&GetOptions("debug!" => \$debug,
	    "test!" => \$test,
            "help!" => \$help,
            "verbose!" => \$verbose,
	    "no-backup!" => \$no_backup,
            "logfile=s" => \$logfile,
            "old-url-prefix=s" => \$old_url_prefix,
            "new-url-prefix=s" => \$new_url_prefix,
            "dir-is-source!" => \$dir_is_source,
            "dir-is-destination!" => \$dir_is_destination);

&help if $help;                        # does the user need help? (probably)

# Other stuff

my $dir = shift;                       # where's the stuff?

if ($dir =~ m/\\/oi) {
  $dir =~ s#\\#/#goi;                  # fix DOSish paths ('\' -> '/')
}


if ($no_backup) {
  $backup = 0;
} else {
  $backup = 1;
}

# Sanity checks (required elements and such)

&help unless $dir;

&help if ($dir_is_source and $dir_is_destination);
&help if not ($dir_is_source or $dir_is_destination);
&help if not ($new_url_prefix and $new_url_prefix);

&debug("Running in test mode.") if $test;
&debug("Running in real mode.") if not $test;
&debug("Will create backups of changed files.") if $backup;
&debug("Will not create backups of changed files.") if not $backup;
&debug("Directory is $dir.");
&debug("Directory is a source.") if $dir_is_source;
&debug("Directory is a destination.") if $dir_is_destination;
&debug("Log file is: $logfile") if $logfile;
&debug("Debugging is on.") if $debug;
&debug("Verbosity is on.") if $verbose;
&debug("New URL Prefix is: $new_url_prefix.") if $new_url_prefix;
&debug("Old URL Prefix is: $old_url_prefix.") if $old_url_prefix;

my $short_old_url_prefix;
my $short_new_url_prefix;

my $old_server_url;
my $new_server_url;

if ($old_url_prefix) {                 # get just the dir piece
  $old_url_prefix =~ m#http://.+?/([^/]+)#;
  $short_old_url_prefix = $1;

  $old_url_prefix =~ m#http://(.+?)/#oi;
  $old_server_url = "http://$1/";
} # end if

if ($new_url_prefix) {                 # get just the dir piece
  $new_url_prefix =~ m#http://.+?/([^/]+)#;
  $short_new_url_prefix = $1;

  $new_url_prefix =~ m#http://(.+?)/#oi;
  $new_server_url = "http://$1/";
}

&debug("Short Old URL Prefix is: $short_old_url_prefix.") if $old_url_prefix;
&debug("Short New URL Prefix is: $short_new_url_prefix.") if $new_url_prefix;

die "Please specify URL prefixes completely...\n" unless
  ($short_new_url_prefix and $short_old_url_prefix);

&debug("Old Server URL is: $old_server_url.");
&debug("New Server URL is: $new_server_url.");

# We appear to be sane, so get started...

find \&process_file, $dir;

# other stats

print "Summary\n";
print "  $total_changes changes.\n";
print "  $total_files_changed file changed.\n";
print "  $total_files_seen files seen.\n";

exit;

# subs

# ------------------------------------------------------ #

sub help()  {

  print<<EOH;

Usage: $0 [options] directory

  Available options: ('*' denotes a required flag)

     --debug
     --help
     --test
     --no-backup
     --verbose
     --logfile "path/to/file"
   * --old-url-prefix "http://old.url.com/old/"
   * --new-url-prefix "http://new.url.com/new/"
   * --dir-is-source
   * --dir-is-destination

  See the manpage for details.

EOH

  exit;

} # end sub

# ------------------------------------------------------ #

sub debug() {

  my $msg = shift;
  return unless $debug;
  print "$msg\n";

} # end sub

# ------------------------------------------------------ #

sub verbose() {

  my $msg = shift;
  return unless ($verbose or $debug);
  print "$msg\n";

} # end sub

# ------------------------------------------------------ #

sub verbose_only() {

  my $msg = shift;
  return unless (!$debug and $verbose);
  print "$msg\n";

} # end sub

# ------------------------------------------------------ #

# This sub is called from the find() function in File::Find,
# so it's a bit ... uh ... special. It protects $_, it makes
# use of some global variables, because passing paramters
# would probably be wateful and awkward.

# For our purposes, we need to find and replace links which may appear
# in any of the following:
#
#  <A HREF="...">
#  <IMG SRC="...">
#  <FORM ... ACTION="...">
#  <LINK ... HREF="...">
#  <BODY BACKGROUND="...">
#  <INPUT SRC="...">
#
# In all cases, we're gonna slurp the whole file into memory and
# run several regexes on it to fix up all the links we can. We'll
# also try to do some reporting as the process goes along.
#
# We'll have to make sure that all the matches are done in a case-
# insensitive manner and that they span wrapped lines.

# I think at this point it's silly to worry about checking the
# recursion depth and running regexes against the `right' number
# of concatenated '../../' strings to see if some of those slipped
# in there. It's *much* easier to make the assumption that top-level
# directories on virtual servers are mostly self-contained and that
# the few references they happen to have to content on the same
# (or formerly same) virtual server are either `Server' fully
# qualified (meaning that they contain a server name) or are
# `Directory' fully qualified (meaning that they start with an
# absolute directory path.


sub process_file () {
  my $changes = 0;              # keep track of changes
  my $pad = "   ";              # visual output padding
  my $file = $_;                # current `file' to process
  my $dir = $File::Find::dir;   # get the relative path
  my $data;                     # where the file will be in memory
  my $time;                     # see when this happens
  local($_);                    # protect $_ so that find() doesn't freak

  return if -d $file;           # skip directories
                                # skip non-html files
  return unless $file =~ /\.htm[l]?$/oi;

  $total_files_seen++;

  $time = localtime(time);
  &debug("Starting at $time.");
  &debug("Processing $dir/$file.");

  &verbose_only("$dir/$file");

  my $stat = stat($file);
  my $size = $stat->size;

  &debug("$pad Size is $size bytes.");

  if ($size == 0) {
    &debug("$pad Skipping.");
    return;
  } # end if

  # Read the file

  &debug("$pad Reading file.");

  open(FILE, "<$file") or do {
    &warn("Error reading $file.");
    exit 10;
  };
  while(<FILE>) {
    $data .= $_;
  }
  close(FILE);

  $_ = $data;

  my $num_matches;

  # Do the real work here... (This will be interesting.)

  #  <A HREF="...">
  #  <IMG SRC="...">
  #  <FORM ... ACTION="...">
  #  <LINK ... HREF="...">
  #  <BODY BACKGROUND="...">
  #  <INPUT SRC="...">

  my %attribute = (); # tag/attribute look-up

  # This is a bit experimental, but should reduce code bloat and
  # typos on my part. It may slow things down to to regex re-
  # compilation, but I'm not sure yet.

  %attribute = (
		A     => "HREF",
		IMG   => "SRC",
		FORM  => "ACTION",
		LINK  => "HREF",
		BODY  => "BACKGROUND",
		INPUT => "SRC"
	       );

  # Very cool. Works like a charm. :-)

  
  if ($dir_is_source) {

    my $T; # tag
    my $A; # attribute

    foreach $T (keys %attribute) {

      $A = $attribute{$T};

      # Part 1

      # Part 1, Case 1
      # Server fully qualified links...
      # http://old.url.com/old/foo.html -> http://new.url.com/new/foo.html
      #
      # Works!
      &debug("$pad Searching <$T $A> for links to to $old_url_prefix.");
      $num_matches = s/<\s*$T\s+([^>]*?)\s*$A\s*=\s*"($old_url_prefix)(.*?)"/<$T $1 $A="$new_url_prefix$3"/gimx;
      $num_matches = 0 unless $num_matches;
      &debug("$pad $num_matches matches found.");
      $changes += $num_matches;

      # Part 1, Case 1
      # Directory fully qualified links...
      # /old/foo.html -> http://new.url.com/new/foo.html
      #
      # Works!
      &debug("$pad Searching <$T $A> for links to /$short_old_url_prefix/.");
      $num_matches = s/<\s*$T\s+([^>]*?)\s*$A\s*=\s*"\/($short_old_url_prefix)\/(.*?)"/<$T $1 $A="$new_url_prefix$3"/gimx;
      $num_matches = 0 unless $num_matches;
      &debug("$pad $num_matches matches found.");
      $changes += $num_matches;


    } # end foreach

  } else {

    # Part 2
    # 'inverse logic' search... (dir is dest)
    
    # is this necessary when $short_old_url_prefix = new one?
    # I think not! Let's fix that later...

    # /old/foo.html -> /new/foo.html
    # /!old/ -> http://old.url.com/!old/
    # http://old.url.com/old/foo.html -> /new/foo.html
    #
    # There is NO CHECK for /foo.html -> http://old.url.com/foo.html

    my $T; # tag
    my $A; # attribute

    foreach $T (keys %attribute) {

      $A = $attribute{$T};

      # Part 2, Case 1
      # Directory fully qualified links... (to the old server)
      # /!old/ -> http://old.url.com/!old/
      #
      # BROKEN!!! Matches WAY too much stuff!
      &debug("$pad Seraching <$T $A> for links to /!$short_old_url_prefix/.");
      $num_matches = s/<\s*$T\s+([^>]*)\s*$A\s*=\s*"\/(?!$short_old_url_prefix\/)(.*?)\/(.*?)"/<$T 1 $1 $A="$old_server_url$2\/$3"/gimx;
      $num_matches = 0 unless $num_matches;
      &debug("$pad $num_matches matches found.");
      $changes += $num_matches;

      # Part 2, Case 2
      # Directory fully qualified links...
      # /old/foo.html -> /new/foo.html
      #
      # Works!
      &debug("$pad Seraching <$T $A> for links to /$short_old_url_prefix/.");
      $num_matches = s/<\s*$T\s+([^>]*)\s*$A\s*=\s*"\/($short_old_url_prefix)\/(.*?)"/<$T 2 $1 $A="\/$short_new_url_prefix\/$3"/gimx;
      $num_matches = 0 unless $num_matches;
      &debug("$pad $num_matches matches found.");
      $changes += $num_matches;

      # Part 2, Case 3
      # Server fully qualified links...
      # http://old.url.com/old/foo.html -> /new/foo.html
      #
      # Works!
      &debug("$pad Searching <$T $A> for links to to $old_url_prefix.");
      $num_matches = s/<\s*$T\s+([^>]*?)\s*$A\s*=\s*"($old_url_prefix)(.*?)"/<$T 3 $1 $A="\/$short_new_url_prefix\/$3"/gimx;
      $num_matches = 0 unless $num_matches;
      &debug("$pad $num_matches matches found.");
      $changes += $num_matches;


    } # end foreach

  } # end if

  # okay, this file is done in memory, let's write it out and
  # such

  &debug("$pad $changes changes made.");

  &verbose_only("$changes changes made.");

  $total_changes += $changes;

  if ($changes == 0) {
    &debug("$pad File is unchanged. No backup made.");
  } else {
    $total_files_changed++;
    # make backup copy using copy()
    if (not $test) {
      if ($backup) {
	copy($file,"$file.bak") or do {
	  &warn("Error copying $file to $file.bak.");
	  exit 10;
	};
	&debug("$pad File is changed. Backup made.");
	# re-write current file from memory if copy() was okay
      } else {
	&debug("$pad File is changed. No backup made, as requested.");
      }
      open(FILE, ">$file") or do {
	&warn("Error writing $file.");
	exit 10;
      };
      print FILE $_;  
      close(FILE);

      $stat = stat($file);
      $size = $stat->size;

      &debug("$pad Size is now $size bytes.");

    } else {
      &debug("$pad File is changed. No backup made in test mode.");
    } # end if

  } # end if

  $time = localtime(time);
  &debug("Finishing at $time.");
  &verbose_only("");


} # end sub

# ------------------------------------------------------ #

# ------------------------------------------------------ #





