#!/bin/bash
CDIR=`pwd`
. ./stop-nginx.sh
/usr/sbin/nginx -p $CDIR -c $CDIR/nginx-big-upload-test.conf &
sleep 1
