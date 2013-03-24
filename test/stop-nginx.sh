#!/bin/bash
CDIR=`pwd`
/usr/sbin/nginx -s stop -p $CDIR -c $CDIR/nginx-big-upload-test.conf