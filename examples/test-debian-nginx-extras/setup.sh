#!/bin/bash

export DEBIAN_FRONTEND=noninteractive \
&& apt-get update \
&& apt-get -y install --no-install-recommends nginx-extras zlib1g-dev libssl-dev

# NOT FOR PROD - this is only to run tests to confirm everything works fine, Ruby will be installed to run the test scripts
/opt/nginx-big-upload/test/run_test_env.sh