#!/bin/bash
#This script runs working directory project tests using latest docker image with nginx-big-upload
SCRIPTDIR=$(dirname "$(readlink -f "$0")")
docker run --rm -it \
 -v ${SCRIPTDIR}/../..:/opt/nginx-big-upload \
 -e DOCKER=1 pgaertig/nginx-big-upload:latest \
 /opt/nginx-big-upload/test/run_test_env.sh

