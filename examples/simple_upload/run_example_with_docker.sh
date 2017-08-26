#!/bin/bash
#This script runs working directory project tests using latest docker image with nginx-big-upload
SCRIPTDIR=$(dirname "$(readlink -f "$0")")
echo "simple_uplaod example will be available at http://127.0.0.1:8089/"
docker run --rm -it \
 -v ${SCRIPTDIR}/../..:/opt/nginx-big-upload \
 -v ${SCRIPTDIR}/nginx.conf:/etc/nginx/nginx.conf \
 -v ${SCRIPTDIR}/index.html:/var/www/index.html \
 --net host \
 -e DOCKER=1 \
 -e ACCESS_LOG_STDOUT=1 \
 -e ERROR_LOG_STDERR=1 \
 -e AUTORELOAD=1 \
 -e AUTORELOAD_CHECK_INTERVAL=5 \
 -e AUTORELOAD_DEBUG=1 \
 pgaertig/nginx-big-upload:latest

