#!/bin/bash
SCRIPTDIR=$(dirname "$(readlink -f "$0")")
docker run --rm -it \
 -v ${SCRIPTDIR}/../..:/opt/nginx-big-upload \
 -v ${SCRIPTDIR}/setup.sh:/opt/setup.sh \
 -e DOCKER=1 \
 debian:stretch-slim \
 /opt/setup.sh
