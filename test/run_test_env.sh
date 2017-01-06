#!/bin/bash

if [ -z "$DOCKER" ]; then echo "This script is intended to be run within Docker container" ; fi

set -ex

echo "Starting pgaertig/nginx-big-upload test environment with:"

/mnt/docker/nginx -V

export DEBIAN_FRONTEND=noninteractive

apt-get -qq update
apt-get -qq install ruby2.3 zlib1g-dev libssl1.0-dev

cd /mnt/test

# Logs forwarded to the console:
mkdir -p /var/log/nginx
#ln -sf /dev/stdout /var/log/nginx/access.log
ln -sf /dev/stderr /var/log/nginx/error.log

./start-nginx.sh

gem install net-http2 --no-ri --no-rdoc --version=0.14.1
ruby test_suite.rb



