#!/bin/bash

if [ -z "$DOCKER" ]; then echo "This script is intended to be run within Docker container" ; fi

set -ex


export \
  NGINX_VERSION=1.31.5 \
  LUAJIT_VERSION=2.1-20260415 \
  LUAJIT_MAJOR_VERSION=2.1 \
  NGINX_DEVEL_KIT_VERSION=0.3.4 \
  LUA_NGINX_MODULE_VERSION=0.10.31 \
  LUA_RESTY_CORE_VERSION=0.1.34rc3 \
  LUA_RESTY_LRUCACHE_VERSION=0.15 \
  MODZIP_COMMIT=a69147f1f9e4486363fd9e6c293aa427747cbc25 \
  UPLOAD_PROGRESS_MODULE_VERSION=0.9.3


# Prepare environment for build:

export DEBIAN_FRONTEND=noninteractive
apt-get -qq update && apt-get -y -qq --auto-remove dist-upgrade
apt-get -qq install -y --no-install-recommends ca-certificates build-essential curl libpcre2-dev zlib1g-dev libssl-dev


# Setup directories:

cd /usr/src
LUAJIT_PATH=$(pwd)/luajit2-${LUAJIT_VERSION}
NGINX_DEVEL_KIT_PATH=$(pwd)/ngx_devel_kit-${NGINX_DEVEL_KIT_VERSION}
LUA_NGINX_MODULE_PATH=$(pwd)/lua-nginx-module-${LUA_NGINX_MODULE_VERSION}
LUA_RESTY_CORE_PATH=$(pwd)/lua-resty-core-${LUA_RESTY_CORE_VERSION}
LUA_RESTY_LRUCACHE_PATH=$(pwd)/lua-resty-lrucache-${LUA_RESTY_LRUCACHE_VERSION}
NGINX_SRC_PATH=$(pwd)/nginx-${NGINX_VERSION}
MODZIP_PATH=$(pwd)/mod_zip-${MODZIP_COMMIT}
UPLOAD_PROGRESS_MODULE_PATH=$(pwd)/nginx-upload-progress-module-${UPLOAD_PROGRESS_MODULE_VERSION}

# Download sources:

curl -fsSL https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz | tar xz
curl -fsSL https://github.com/openresty/luajit2/archive/refs/tags/v${LUAJIT_VERSION}.tar.gz | tar xz
curl -fsSL https://github.com/vision5/ngx_devel_kit/archive/refs/tags/v${NGINX_DEVEL_KIT_VERSION}.tar.gz | tar xz
curl -fsSL https://github.com/openresty/lua-nginx-module/archive/refs/tags/v${LUA_NGINX_MODULE_VERSION}.tar.gz | tar xz
curl -fsSL https://github.com/openresty/lua-resty-core/archive/refs/tags/v${LUA_RESTY_CORE_VERSION}.tar.gz | tar xz
curl -fsSL https://github.com/openresty/lua-resty-lrucache/archive/refs/tags/v${LUA_RESTY_LRUCACHE_VERSION}.tar.gz | tar xz
# mod_zip fork with optional "size@timestamp" in the file list, generated parser included
curl -fsSL https://github.com/pgaertig/mod_zip/archive/${MODZIP_COMMIT}.tar.gz | tar xz
curl -fsSL https://github.com/masterzen/nginx-upload-progress-module/archive/refs/tags/v${UPLOAD_PROGRESS_MODULE_VERSION}.tar.gz | tar xz

# LuaJIT - build and install

(cd $LUAJIT_PATH && make -j$(nproc) && make install)
ln -sf luajit-${LUAJIT_MAJOR_VERSION}* /usr/local/bin/luajit
echo /usr/local/lib > /etc/ld.so.conf.d/luajit.conf
ldconfig
export LUAJIT_LIB=/usr/local/lib
export LUAJIT_INC=/usr/local/include/luajit-${LUAJIT_MAJOR_VERSION}

# lua-resty-core and lua-resty-lrucache - pure Lua, mandatory since lua-nginx-module 0.10.16.
(cd $LUA_RESTY_LRUCACHE_PATH && make install PREFIX=/usr/local LUA_LIB_DIR=/usr/local/share/lua/5.1)
(cd $LUA_RESTY_CORE_PATH && make install PREFIX=/usr/local LUA_LIB_DIR=/usr/local/share/lua/5.1)


# Nginx - build and install
cd $NGINX_SRC_PATH

# -Wl,-E exports the nginx symbol table. lua-resty-core reaches the ngx_http_lua_ffi_* symbols in the
# nginx binary through the FFI, and without this nginx starts fine but dies on the first Lua request.

./configure \
  --sbin-path=/usr/sbin/nginx \
  --conf-path=/etc/nginx/nginx.conf \
  --http-log-path=/var/log/nginx/access.log --error-log-path=/var/log/nginx/error.log \
  --pid-path=/run/nginx.pid \
  --with-pcre-jit \
  --with-http_v2_module \
  --with-http_v3_module \
  --with-http_ssl_module \
  --with-http_gzip_static_module \
  --with-http_addition_module \
  --with-http_realip_module \
  --with-http_stub_status_module \
  --with-file-aio \
  --with-threads \
  --with-cc-opt="-O2" \
  --with-ld-opt="-Wl,-E -Wl,-rpath,/usr/local/lib" \
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

make -j$(nproc)
make install

# The binary is now dynamically linked, so the runtime libraries have to survive the purge below.
# zlib1g and libssl3 are safe because zlib1g-dev and libssl-dev stay installed for the Lua FFI, but
# libpcre2-8-0 would go away together with libpcre2-dev unless it is requested explicitly.
apt-get -qq install -y --no-install-recommends libpcre2-8-0

# Purge build deps
apt-get -qq purge -y --auto-remove curl build-essential libpcre2-dev
