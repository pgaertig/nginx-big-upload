#!/usr/bin/dumb-init /bin/bash

set -m

USER_ID=${NGINX_USER_ID:-1000}
GROUP_ID=${NGINX_GROUP_ID:-1000}

groupmod -g ${GROUP_ID} nginx
usermod -u ${USER_ID} -g nginx -G www-data nginx

[[ $ACCESS_LOG_STDOUT ]] && ln -sf /dev/stdout /var/log/nginx/access.log
[[ $ERROR_LOG_STDERR ]] && ln -sf /dev/stderr /var/log/nginx/error.log

echoerr() { printf "%(%FT%TZ)T %s\n" -1 "$*" >&2; }

#Checks
nginx -t -g 'daemon off;' || ( echoerr "Nginx configuration test failed" && exit 1 )

#Run nginx graceful autoreload check in background
[[ $AUTORELOAD ]] && (
    sleep 1
    [[ "$AUTORELOAD_CHECK_METHOD" = "timestamp" ]] && CHECK_METHOD='timestamp' || CHECK_METHOD='checksum'

    echoerr "Autoreload: Waiting for ${AUTORELOAD_CHECK_FILE:=/etc/nginx/nginx.conf} changes to autoreload nginx." \
         "Check interval is ${AUTORELOAD_CHECK_INTERVAL:=60} seconds with $CHECK_METHOD check."

    [[ "$CHECK_METHOD" = "timestamp" ]] && CHECK_CMD="stat -c%Y $AUTORELOAD_CHECK_FILE" || CHECK_CMD="sha1sum $AUTORELOAD_CHECK_FILE"
    [ "$AUTORELOAD_CHECK_INTERVAL" -gt 0 ] 2>/dev/null || echoerr "AUTORELOAD_CHECK_INTERVAL must be grater than 0, is: ${AUTORELOAD_CHECK_INTERVAL}"

    LAST_CHECK=($($CHECK_CMD))

    while :; do
      [ ! -r ${AUTORELOAD_CHECK_FILE} ] && echoerr "File $AUTORELOAD_CHECK_FILE is not readable for autoreload" && exit 2

      sleep $AUTORELOAD_CHECK_INTERVAL
      CURRENT_CHECK=($($CHECK_CMD))

      [[ $AUTORELOAD_DEBUG ]] && echoerr "Autoreload: debug LAST_CHECK:$LAST_CHECK CURRENT_CHECK:$CURRENT_CHECK"

      if [ "$LAST_CHECK" != "$CURRENT_CHECK" ] ; then
        LAST_CHECK="$CURRENT_CHECK"
        sleep 5 #Debounce in case some other configuration files are changed with some delay
        echoerr "Autoreload: $1 changed - reloading nginx"
        nginx -t && nginx -s reload
      fi
    done
) &

exec nginx -g 'daemon off;'
