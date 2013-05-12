#!/bin/bash
CDIR=`pwd`
if [ -f ./nginx ]
then
  NGINX_BIN=./nginx
else
  NGINX_BIN=`which nginx`
fi
. ./stop-nginx.sh
echo "Using $NGINX_BIN"
$NGINX_BIN -v
$NGINX_BIN -p $CDIR -c $CDIR/nginx-big-upload-test.conf
sleep 1

