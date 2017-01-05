#!/bin/sh
docker run --rm -it -v $(pwd):/mnt busybox /mnt/nginx -V

