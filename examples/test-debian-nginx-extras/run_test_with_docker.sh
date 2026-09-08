#!/bin/bash
SCRIPTDIR=$(dirname "$(readlink -f "$0")")
docker run --rm -i ${DOCKER_TTY:--t} \
 -v ${SCRIPTDIR}/../..:/opt/nginx-big-upload \
 -v ${SCRIPTDIR}/setup.sh:/opt/setup.sh \
 -e DOCKER=1 -e RUN_ONCE \
 debian:trixie-slim \
 /opt/setup.sh
