#!/bin/bash
CDIR=`pwd`
if [ -f ./nginx ]
then
  NGINX_BIN=./nginx
else
  NGINX_BIN=`which nginx`
fi
. ./stop-nginx.sh
echo "Using $NGINX_BIN (Ctrl+C to stop)"
$NGINX_BIN -p $CDIR -c $CDIR/nginx-big-upload-example.conf
