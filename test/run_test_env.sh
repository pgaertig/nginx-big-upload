#!/bin/bash -l

if [ -z "$DOCKER" ]; then echo "This script is intended to be run within Docker container.\nPlease run one script in examples/test-* ." ; fi

set -ex

echo "Starting pgaertig/nginx-big-upload test environment with:"

NGINX_BIN=`which nginx`
TEST_DIR=/opt/nginx-big-upload/test

$NGINX_BIN -V

# Logs forwarded to the console:
mkdir -p /var/log/nginx
#ln -sf /dev/stdout /var/log/nginx/access.log
ln -sf /dev/stderr /var/log/nginx/error.log

export DEBIAN_FRONTEND=noninteractive
export TERM=xterm
apt-get -qqy update
apt-get -qqy install --no-install-recommends ruby curl openssl

# The HTTP/3 vhost self-signed certs
if [ ! -f /tmp/nbu-test-cert.pem ]; then
  openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj /CN=localhost \
    -keyout /tmp/nbu-test-key.pem -out /tmp/nbu-test-cert.pem
fi

$NGINX_BIN -t -c $TEST_DIR/nginx-big-upload-test.conf

. /etc/profile
. /root/.profile
env

cd $TEST_DIR
trap 'echo "Exiting" ; exit' INT

set +xe
while true
do
  $NGINX_BIN -c $TEST_DIR/nginx-big-upload-test.conf
  ruby test_suite.rb
  TEST_EXIT_CODE=$?
  $NGINX_BIN -s stop -c $TEST_DIR/nginx-big-upload-test.conf
  if [ -z "$RUN_ONCE" ]; then
    read -p $'Press Enter to rerun tests or Ctrl+C to exit...\n'
  else
    echo "Tests run once with exit code: $TEST_EXIT_CODE"
    exit $TEST_EXIT_CODE
  fi
done
