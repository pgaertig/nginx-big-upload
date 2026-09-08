#!/bin/bash
#This script runs working directory project tests using docker image with nginx-big-upload.
SCRIPTDIR=$(dirname "$(readlink -f "$0")")
docker run --rm -i ${DOCKER_TTY:--t} \
 -v ${SCRIPTDIR}/../..:/opt/nginx-big-upload \
 -e DOCKER=1 -e RUN_ONCE ${NBU_IMAGE:-pgaertig/nginx-big-upload:latest} \
 /opt/nginx-big-upload/test/run_test_env.sh

