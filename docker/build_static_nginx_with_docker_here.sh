#!/bin/bash
#This script builds static nginx in docker sandbox and extracts it into current directory.
#Use to obtain executable manualy. For automated deployments top direcory Dockerfile is recommended.

docker run --rm -it -v $(pwd):/mnt \
  -e DOCKER=1 \
  -e TARGET_DIR=/mnt \
  -e TARGET_GID=$(id --group) \
  -e TARGET_UID=$(id --user) \
  debian:stretch-slim /mnt/build_nginx.sh

$(pwd)/nginx -v
