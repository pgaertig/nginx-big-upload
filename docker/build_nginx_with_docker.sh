#!/bin/bash
docker run --rm -it -v $(pwd):/mnt -e GID=$(id --group) -e UID=$(id --user) -e DOCKER=1 debian:unstable /mnt/build_nginx.sh

