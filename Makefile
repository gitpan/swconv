# swconv makefile.

# $Id: Makefile,v 1.1 1998/09/19 20:19:07 jzawodn Exp jzawodn $

all: swconv.1 swconv.html swconv.txt swconv.ok

clean:
	rm -f swconv.1
	rm -f swconv.html
	rm -f swconv.txt

swconv.1: swconv.pod
	pod2man swconv.pod > swconv.1

swconv.html: swconv.pod
	pod2html swconv.pod > swconv.html

swconv.txt: swconv.pod
	pod2text swconv.pod > swconv.txt

swconv.ok: swconv.pl
	perl -cw swconv.pl
