#!/bin/bash

cp orig/s.html source
cp orig/d.html destination

perl swconv.pl --test --old-url-prefix "http://shared-web.moc.com/benadm/" --new-url-prefix "http://mweb.fdy.moc.com/benadm/" --dir-is-source source

#perl swconv.pl --test --debug --old-url-prefix "http://shared-web.moc.com/benadm/" --new-url-prefix "http://mweb.fdy.moc.com/benadm/" --dir-is-destination destination
