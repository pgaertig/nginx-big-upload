#!/bin/bash
SCRIPTDIR=$(dirname "$(readlink -f "$0")")
docker run --rm -it \
 -v ${SCRIPTDIR}/../..:/opt/nginx-big-upload \
 -v ${SCRIPTDIR}/setup.sh:/opt/setup.sh \
 -e DOCKER=1 \
 ubuntu:16.04 \
 /opt/setup.sh
