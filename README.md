# nginx-big-upload

Written in Lua provides reliable uploads and easy to extend logic of file upload lifecycle.
Currently only PUT/POST RAW body resumable uploads are supported. These are compatible with [nginx-upload-module](https://github.com/vkholodkov/nginx-upload-module/tree/2.2) resumable
requests. This extension requires Nginx compiled with Lua, see [Installation](#Installation) below.

## Features

- PUT/POST uploads,
- Partial chunked and resumable uploads,
- On the fly resumable CRC32 checksum calculation (client-side state),
- On the fly resumable SHA-1
- `nginx-upload-module` resumable protocol compatibility,

## Status and compatibility

This module in production since 4th Apr 2013 on author's services with usage ~50GB/day, ~100 users/day with various web browsers.
Tested with:

- production: v1.0.0 - v1.1.0, nginx-1.2.7 (Ubuntu, Debian), nginx-lua-module v0.7.9
- tests: v1.1.0, nginx-1.4.1 (Ubuntu, Debian), nginx-lua-module v0.8.0 built-in stock nginx-extras DEB.

## <a id="Installation"></a> Installation

This module requires LuaJIT and nginx with [HttpLuaModule](http://wiki.nginx.org/HttpLuaModule) installed in your system.
If you work with Ubuntu (12.04 Precise Pangolin LTS) follow these steps:

- Install LuaJIT using official packages or from [LuaJIT source](http://www.lua.org/) which should be up-to-date.

        sudo apt-get install luajit

- You have to build nginx from sources with Lua module and LuaJIT support. Precompiled nginx packages depend on Lua interpreter instead of faster LuaJIT.

        #register PGP keys
        wget --quiet -O - http://nginx.org/keys/nginx_signing.key | sudo apt-key add -

        #Create /etc/apt/sources.list.d/nginx-stable.list with these entries
        deb http://ppa.launchpad.net/nginx/stable/ubuntu precise main
        deb-src http://ppa.launchpad.net/nginx/stable/ubuntu precise main

        #Update package lists
        sudo apt-get update

        #Create and go to directory for nginx source and compilation task, e.g. ~/mynginx,
        #This will download nginx sources with Ubuntu/Debian package configs
        sudo apt-get source nginx
        sudo apt-get build-dep nginx

        #Export LuaJIT paths. Find them with `locate libluajit`

        export LUAJIT_LIB=/usr/lib/x86_64-linux-gnu
        export LUAJIT_INC=/usr/include/luajit-2.0

        #Go to
        cd ~/mynginx/nginx-1.4.1

        #Edit debian/rules to remove modules you don't need in nginx-extras configuration,
        #eventually reconfigure nginx-full. Run build next:
        dpkg-buildpackage -b

        #Build goes here...

        #Install nginx-extras
        sudo dpkg -i nginx-extras_1.4.1-1ppa0~precise_amd64.deb

        #Ensure nginx is in proper version
        nginx -v
        # Output: nginx version: nginx/1.4.1

        #Ensure nginx depends on LuaJIT
        ldd `sudo which nginx`
        # Should output line similar to:
        #   libluajit-5.1.so.2 => /usr/local/lib/libluajit-5.1.so.2 (0x00002aec3f2a2000)
        #   libluajit-5.1.so.2 => /usr/lib/x86_64-linux-gnu/libluajit-5.1.so.2 (0x00007f702a8b1000)
        # The important is to have word `jit`, without it nginx will use base
        # Lua interpreter, check LUAJIT paths.

- Download `nginx-big-upload` files e.g. into `/opt` directory of your server. Set up `$package_path` variable and `content_by_lua_file` directive to dowload location. Remember that all relative paths are relative to nginx config file.

- Optional: Ruby 2.0 is required to run tests from `test` directory, [RVM](https://rvm.io/rvm/install/) use is recommended.

## Configuration

Below is example configuration in nginx configuration file:

     set $storage backend_file;
     set $file_storage_path /tmp;
     set $backend_url /files/add;

     set $bu_sha1 on;
     set $bu_checksum on;

     set $package_path '/opt/nginx-big-upload/?.lua';
     content_by_lua_file /opt/nginx-big-upload/big-upload.lua;

### `$storage`
The available values are `backend_file` and `file`.
With `file` the uploaded file is saved to disk under `$file_storage_path` directory. Every succesfully uploaded chunk request responds with HTTP code `201 Created`.
The `backend_file` works same as `file` except successful upload of last chunk invokes the backend specified in `$backend_url`.
### `$file_storage_path`
This variable should contain path where uploaded files will be stored. File names same as `X-Session-Id` header value sent by the client. For security the header value can only contain
alphanumeric characters (0-9,a-z,A-Z). The `X-Session-Id` is also returned in response on every succesful chunk. The response body of each chunk shows exposes current range of file uploaded so far, e.g. `0-4095/1243233`.

### `$backend_url`
When `$storage` is set to `backend_file`, the requests are handled the same as `file` option with `$file_storage_path`. However after last chunk is successfuly uploaded the backend `$backend_url` is invoked and its response returned to client.
Remember to declare a backend location with `internal;` nginx directive to prevent external requests. Named locations are not supported with `$backend_url`, e.g. `@rails_app`, but there is simple workaround for it:

    location /files/add {
     internal;
     access_log off;
     content_by_lua 'ngx.exec("@rails_app")';
    }

With the above example the last chunk's success request processing will be forwarded to `@rails_app` named location.

This variable contains a location which will be invoked when file upload is complete. This is only done when backend handler is enabled by `$storage backend_file;`.
The request sent to backend will be POST request with url-encoded body params:

* `id` - identifier of file, sent in `X-Session-ID`;
* `name` - name of file extracted from `Content-disposition` request header;
* `path` - server-side path to uploaded file;
* `checksum` - optional CRC32 checksum - see `$bu_checksum` setting;
* `sha1` - optional SHA-1 hex string - see `$bu_sha1` setting;

### `$bu_sha1 on`
This variable enables on-the-fly hash calculation of SHA-1 on uploaded content. The result will be returned to client in `X-SHA1` header as hexadecimal string.
Client can provide `X-SHA` header in request so then server will verify it on the end of each chunk.
If resumable upload is performed then both headers should contain hash of data uploaded so far and both are compared on the end of each chunk.
For security reasons SHA-1 context in between chunks is stored on the server in the same path as uploaded file plus additional `.shactx` extension.
Using client-side state as with CRC32 checksum calculation is not possible.

### `$bu_checksum on` (CRC32)
This option enables CRC32 calculation on server-side. For single part upload the server will return `X-Checksum` response header with CRC32 hex value (up to 8 characters).
User can also provide `X-Checksum` header in request then the server will compare checksums after complete upload and fail on mismatch.

When resumable upload is used then the client has to pass CRC32 result of recently uploaded chunk to following chunk using `X-Last-Checksum` request header.
Thanks to this the client keeps the checksum state between chunks and server can calculate the correct checksum for whole upload.

## Example client-server conversation with resumable upload

    #First chunk:

    > PUT /upload
    > X-Session-Id: 123456789
    > Content-Range: bytes 0-4/10
    > Content-disposition: attachement; filename=document.txt    #You can use UTF-8 file names
    >
    > Part1

    < 201 Created
    < X-Checksum: 3053a846
    < X-SHA1: 138d033e6d97d507ae613bd0c29b7ed365f19395           #SHA-1 of data uploaded so far

    #Last chunk:

    > PUT /upload                                                #Next chunk, actually final one
    > X-Session-Id: 123456789
    > Content-Range: bytes 5-9/10
    > Content-Disposition: attachement; filename=document.txt    #Only used after last chunk actually
    > X-Last-Checksum: 3053a846                                  #Pass checksum of previous chunks to continue CRC32
    >
    > Part2

    #Backend subrequest:

       > PUT /files/add
       > X-Session-Id: 123456789
       > Content-Range: bytes 5-9/10
       > Content-Disposition: attachement; filename=document.txt
       > X-Last-Checksum: 3053a846
       >
       > id=123456789&path=/tmp/uploads/123456789&name=document.txt&checksum=478ac3e5&sha1=988dced4ecae71ee10dd5d8ddb97adb62c537704

    #Response from the backend goes to client, plus these headers

    < 200 OK
    < X-Checksum: 478ac3e5
    < X-SHA1: 988dced4ecae71ee10dd5d8ddb97adb62c537704
    <
    < Thanks for document.txt file.

## Differences with nginx-upload-module

I created this module as an user of excellent `nginx-upload-module` which processed terabytes of data for several years. Sometimes I needed
more features which were missing such as CRC32 calculation for resumable uploads. Unfortunately I suspect that module may be abandoned, see [#41](https://github.com/vkholodkov/nginx-upload-module/issues/41),
therefore I started a development of new solution which will work with Nginx 1.3.8+ and will provide some area for enhancement. I prefer to use
Lua module which gives very short development/test iterations in reload per request mode. Here are differences list of this module introduces:

* Linear resumability - there is no way to upload last chunk as first in row, thus there is no risk of bomb file DoS attack. Chunks must be uploaded sequentially, therefore there is also no need to keep fragments layout (`.status` files) on server.
* `nginx-upload-module` doesn't work currently with `nginx` 1.3.9 and newer, see [#41](https://github.com/vkholodkov/nginx-upload-module/issues/41).
* Easy to enhance/fork, Lua modules are easy to develop, it took me 2 days to learn Lua and create first production version.
* Multi-part POST requests (form uploads) are not supported only RAW file in PUT/POST request; check [lua-resty-upload](https://github.com/agentzh/lua-resty-upload);
* No upload rate limit setting - only one client can upload a given file so it is better to throttle downloads.
* `nginx-upload-module` doesn't provide CRC32 or SHA1 calculation in resumable mode.

### Benchmark

Below is the result of `test/performance_test.rb` method `test_final_perf`, which tests nginx-big-upload (bu) vs nginx-upload-module (num)
with chunked upload of identical data to the same backend. Each file is sent in ~512KB chunks which means 51MB file
is transferred in 100 requests. Times in seconds. Fileds user/system/total are rather related to test script execution times, but real is the real one.

                      user       system     total      real
    bu     51MB * 10  0.630000   0.820000   1.450000 (  3.199759)  #nginx 1.2.7
    bu_crc 51MB * 10  0.670000   0.910000   1.580000 (  4.164285)  #nginx 1.2.7
    num    51MB * 10  0.680000   0.920000   1.600000 (  2.677721)  #nginx 1.2.7
    bu    204MB * 10  2.520000   3.510000   6.030000 ( 12.576817)  #nginx 1.2.7
    num   204MB * 10  2.480000   3.940000   6.420000 ( 10.818588)  #nginx 1.2.7

## TODO:
* to describe protocol
* storage handler with back-end subrequest before first chunk - e.g. to check if upload is acceptable or to track temporary file
* upload status requests,
* back-end-side progress notifications,
* cloud pass-thru upload handler,
* multiparts support - this is low priority please use excellent [nginx-upload-module](https://github.com/vkholodkov/nginx-upload-module/tree/2.2) or [lua-resty-upload](https://github.com/agentzh/lua-resty-upload)




