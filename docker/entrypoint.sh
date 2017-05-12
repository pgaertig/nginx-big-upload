#!/usr/bin/dumb-init /bin/bash

set -m

ARF=${AUTORELOAD_FILE:-"/etc/nginx/nginx.conf"}
ART=${AUTORELOAD_TEST_INTERVAL:-"60"}

ln -sf /dev/stdout /var/log/nginx/access.log
ln -sf /dev/stderr /var/log/nginx/error.log

echoerr() { printf "%s\n" "$*" >&2; }

#Checks
nginx -t -g 'daemon off;' || ( echoerr "Nginx configuration test failed" && exit 1 )
[ ! -r $ARF ] && echoerr "File $ARF is not readable for autoreload" && exit 2

#Run
set -ex

#sigterm_handler() {
#  echo "Handling SIGTERM - stopping autoreload & nginx"
#  kill -TERM "$NGINX_AUTORELOAD_PID" 2>/dev/null
#  kill -TERM "$NGINX_PID" 2>/dev/null
#}

#trap sigterm_handler SIGTERM

(nginx -g 'daemon off;' || kill -SIGTERM 1) &
NGINX_PID=$!
sleep 1
(/opt/nginx-big-upload/docker/nginx_autoreload.sh $ARF $ART || kill -SIGTERM 1 ) &
NGINX_AUTORELOAD_PID=$!

wait $NGINX_PID $NGINX_AUTORELOAD_PID



