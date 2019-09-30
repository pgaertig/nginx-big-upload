#!/bin/bash
SCRIPTDIR=$(dirname "$(readlink -f "$0")")
docker run --rm -it \
 -v ${SCRIPTDIR}/../..:/opt/nginx-big-upload \
 -v ${SCRIPTDIR}/setup.sh:/opt/setup.sh \
 -e DOCKER=1 -e RUN_ONCE \
 debian:buster-slim \
 /opt/setup.sh
