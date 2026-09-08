#!/bin/bash -l

# Runs the mod_zip memory stress test (issue #108) inside a container, the same way
# run_test_env.sh runs the unit suite. See test/performance/modzip_memory_test.rb.
#
# Pass MODZIP_FILE_COUNT, MODZIP_MAX_PEAK_GROWTH_KB etc. through with -e to tune the run.

if [ -z "$DOCKER" ]; then echo "This script is intended to be run within Docker container." ; fi

set -e

NGINX_BIN=${NGINX_BIN:-$(which nginx)}
TEST_DIR=/opt/nginx-big-upload/test

echo "Using $NGINX_BIN"
$NGINX_BIN -v

export DEBIAN_FRONTEND=noninteractive
apt-get -qqy update
apt-get -qqy install --no-install-recommends ruby

export NGINX_BIN
exec ruby $TEST_DIR/performance/modzip_memory_test.rb
