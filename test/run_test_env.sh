#!/bin/bash -l

if [ -z "$DOCKER" ]; then echo "This script is intended to be run within Docker container" ; fi

set -ex

echo "Starting pgaertig/nginx-big-upload test environment with:"

NGINX_BIN=`which nginx`
TEST_DIR=/opt/nginx-big-upload/test

$NGINX_BIN -V

export DEBIAN_FRONTEND=noninteractive
export TERM=xterm

apt-get -qqy update
apt-get -qqy install --no-install-recommends ruby2.3

# Logs forwarded to the console:
#ln -sf /dev/stdout /var/log/nginx/access.log
ln -sf /dev/stderr /var/log/nginx/error.log

$NGINX_BIN -t -c $TEST_DIR/nginx-big-upload-test.conf

$NGINX_BIN -p $TEST_DIR -c $TEST_DIR/nginx-big-upload-test.conf

gem install net-http2 --no-ri --no-rdoc --version=0.15.0

. /etc/profile
. /root/.profile
env
cd $TEST_DIR

trap 'echo "Exiting" ; exit' INT
set +xe
while true
do
  ruby test_suite.rb
  read -p $'Press Enter to rerun tests or Ctrl+C to exit...\n'
done
