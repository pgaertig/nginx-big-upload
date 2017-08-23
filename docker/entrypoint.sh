#!/usr/bin/dumb-init /bin/bash

set -m

ARF=${AUTORELOAD_FILE:-"/etc/nginx/nginx.conf"}
ART=${AUTORELOAD_TEST_INTERVAL:-"60"}
USER_ID=${NGINX_USER_ID:-1000}
GROUP_ID=${NGINX_GROUP_ID:-1000}

groupmod -g ${GROUP_ID} nginx
usermod -u ${USER_ID} -g nginx -G www-data nginx

[[ $ACCESS_LOG_STDOUT ]] && ln -sf /dev/stdout /var/log/nginx/access.log
[[ $ERROR_LOG_STDERR ]] && ln -sf /dev/stderr /var/log/nginx/error.log

echoerr() { printf "%s\n" "$*" >&2; }

#Checks
nginx -t -g 'daemon off;' || ( echoerr "Nginx configuration test failed" && exit 1 )
[ ! -r $ARF ] && echoerr "File $ARF is not readable for autoreload" && exit 2

#Run
set -ex

(nginx -g 'daemon off;' || kill -SIGTERM 1) &
NGINX_PID=$!
sleep 1
(/opt/nginx-big-upload/docker/nginx_autoreload.sh $ARF $ART || kill -SIGTERM 1 ) &
NGINX_AUTORELOAD_PID=$!

wait $NGINX_PID $NGINX_AUTORELOAD_PID



