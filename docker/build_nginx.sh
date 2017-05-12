#!/bin/bash

if [ -z "$DOCKER" ]; then echo "This script is intended to be run within Docker container" ; fi

set -ex

# Versions:

export \
  NGINX_VERSION=1.13.4 \
  OPENSSL_VERSION=1.0.2l \
  LUAJIT_VERSION=2.1.0-beta3 \
  LUAJIT_MAJOR_VERSION=2.1 \
  NGINX_DEVEL_KIT_VERSION=0.3.0 \
  LUA_NGINX_MODULE_VERSION=0.10.10 \
  UPLOAD_PROGRESS_MODULE_VERSION=master


# Prepare environment for build:

export DEBIAN_FRONTEND=noninteractive
apt-get -qq update && apt-get -y -qq --auto-remove dist-upgrade
apt-get -qq install -y --no-install-recommends ca-certificates build-essential curl libpcre++-dev zlib1g-dev git


# Setup directories:

cd /usr/src
NGINX_DEVEL_KIT_PATH=$(pwd)/ngx_devel_kit-${NGINX_DEVEL_KIT_VERSION}
LUA_NGINX_MODULE_PATH=$(pwd)/lua-nginx-module-${LUA_NGINX_MODULE_VERSION}
OPENSSL_PATH=$(pwd)/openssl-${OPENSSL_VERSION}
NGINX_SRC_PATH=$(pwd)/nginx-${NGINX_VERSION}
MODZIP_PATH=$(pwd)/mod_zip-master
UPLOAD_PROGRESS_MODULE_PATH=$(pwd)/nginx-upload-progress-module-${UPLOAD_PROGRESS_MODULE_VERSION}

# Download sources:

curl -L http://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz | tar xz
curl -L http://luajit.org/download/LuaJIT-${LUAJIT_VERSION}.tar.gz | tar xz
curl -L https://github.com/simpl/ngx_devel_kit/archive/v${NGINX_DEVEL_KIT_VERSION}.tar.gz | tar xz
curl -L https://github.com/openresty/lua-nginx-module/archive/v${LUA_NGINX_MODULE_VERSION}.tar.gz | tar xz
curl -L https://github.com/evanmiller/mod_zip/archive/master.tar.gz | tar xz
#curl -L https://github.com/masterzen/nginx-upload-progress-module/archive/v${UPLOAD_PROGRESS_MODULE_VERSION}.tar.gz | tar xz
curl -L https://github.com/masterzen/nginx-upload-progress-module/archive/master.tar.gz | tar xz
curl -L https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz | tar xz

# LuaJIT - build and install

(cd LuaJIT-${LUAJIT_VERSION} && make install)
ln -sf luajit-${LUAJIT_VERSION} /usr/local/bin/luajit
ln -sf /usr/local/lib/libluajit-5.1.so /lib/x86_64-linux-gnu/libluajit-5.1.so.2
export LUAJIT_LIB=/usr/local/lib/lua
export LUAJIT_INC=/usr/local/include/luajit-${LUAJIT_MAJOR_VERSION}

# OpenSSL - build and install
(cd $OPENSSL_PATH && ./config no-shared && make && make install)

# Nginx - build and install
cd nginx-${NGINX_VERSION}

#export CFLAGS="-g -O0"

./configure \
  --sbin-path=/usr/sbin/nginx \
  --conf-path=/etc/nginx/nginx.conf \
  --http-log-path=/var/log/nginx/access.log --error-log-path=/var/log/nginx/error.log \
  --pid-path=/run/nginx.pid \
  --with-cpu-opt=generic \
  --with-pcre-jit \
  --with-ipv6 \
  --with-http_v2_module \
  --with-http_ssl_module \
  --with-http_gzip_static_module \
  --with-http_addition_module \
  --with-http_realip_module \
  --with-http_stub_status_module \
  --with-file-aio \
  --with-threads \
  --with-ld-opt="-static" \
  --with-openssl-opt=no-krb5 \
  --with-openssl=$OPENSSL_PATH \
  --with-cc-opt="-O2 -static -static-libgcc" \
  --with-ld-opt="-static -pthread" \
  --add-module=${NGINX_DEVEL_KIT_PATH} \
  --add-module=${LUA_NGINX_MODULE_PATH} \
  --add-module=${MODZIP_PATH} \
  --add-module=${UPLOAD_PROGRESS_MODULE_PATH} \
  --without-http_fastcgi_module \
  --without-http_uwsgi_module \
  --without-http_scgi_module \
  --without-http_memcached_module \
  --without-http_empty_gif_module \
  --without-http_browser_module \
  --without-mail_pop3_module \
  --without-mail_imap_module \
  --without-mail_smtp_module \
#  --with-debug

sed -i "/CFLAGS/s/ \-O //g" objs/Makefile

make -j4
make install

if [ ! -z "$TARGET_DIR" ]; then
  # Extract built nginx outside the container with proper ownership (default root)
  cp objs/nginx ${TARGET_DIR}/
  chown ${TARGET_UID:-0}:${TARGET_GID:-0} ${TARGET_DIR}/nginx
fi

# Purge build deps
apt-get -qq purge -y --auto-remove curl build-essential libpcre++-dev git

