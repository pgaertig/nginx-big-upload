#!/bin/bash
set -ex

# Versions:

export \
  NGINX_VERSION=1.11.7 \
  OPENSSL_VERSION=1.0.2j \
  LUAJIT_VERSION=2.1.0-beta2 \
  LUAJIT_MAJOR_VERSION=2.1 \
  NGINX_DEVEL_KIT_VERSION=0.3.0 \
  LUA_NGINX_MODULE_VERSION=0.10.7 \
  NGINX_INSTALL_PATH=/opt/nginx \
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
./configure \
  --prefix=${NGINX_INSTALL_PATH} \
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
  --without-mail_smtp_module 

sed -i "/CFLAGS/s/ \-O //g" objs/Makefile

make -j4
make install

# Extract built nginx outside the container with proper ownership (default root)
cp objs/nginx /mnt/
chown ${UID:-0}:${GID:-0} /mnt/nginx

exit 0
# TODO BELOW MAKES USE IN CONTAINER ONLY

# Logs forwarded to the console:

mkdir -p /var/log/nginx
ln -sf /dev/stdout /var/log/nginx/access.log
ln -sf /dev/stderr /var/log/nginx/error.log

# Cleanup:

apt-get -qq remove -y --auto-remove curl build-essential libpcre++-dev zlib1g-dev git
rm -rf /src /var/lib/apt/lists/* /tmp/* /var/tmp/* /usr/share/doc /usr/share/doc-base /usr/share/man /usr/share/locale /usr/share/zoneinfo /usr/src


