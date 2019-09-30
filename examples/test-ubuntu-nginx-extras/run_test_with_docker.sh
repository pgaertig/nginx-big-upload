#!/bin/bash
SCRIPTDIR=$(dirname "$(readlink -f "$0")")
docker run --rm -it \
 -v ${SCRIPTDIR}/../..:/opt/nginx-big-upload \
 -v ${SCRIPTDIR}/setup.sh:/opt/setup.sh \
 -e DOCKER=1 -e RUN_ONCE \
 ubuntu:18.04 \
 /opt/setup.sh
