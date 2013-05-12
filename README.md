# nginx-big-upload

Written in Lua provides reliable uploads and easy to extend logic of file upload lifecycle.
Currently only PUT/POST RAW body resumable uploads are supported. These are compatible with [nginx-upload-module](https://github.com/vkholodkov/nginx-upload-module/tree/2.2) resumable
requests. This extension requires Nginx compiled with Lua, see [Installation](#Installation) below.

## Features

- PUT/POST uploads,
- Partial chunked and resumable uploads,
- On the fly resumable CRC32 checksum calculation,
- `nginx-upload-module` resumable protocol compatibility,
- Stateless, there are no other files in file-system other than uploaded file.

## Status and compatibility

This module in production since 4th Apr 2013 on author's services with usage ~50GB/day, ~100 users/day with various web browsers.
Tested with:

- production: v1.0.0 - v1.1.0, nginx-1.2.7 (Ubuntu, Debian), nginx-lua-module v0.7.9
- tests: v1.1.0, nginx-1.4.1 (Ubuntu, Debian), nginx-lua-module v0.8.0 built-in stock nginx-extras DEB.

## <a id="Installation"></a> Installation

This module requires LuaJIT and nginx with [HttpLuaModule](http://wiki.nginx.org/HttpLuaModule) installed in your system.
If you work with Ubuntu (12.04 Precise Pangolin LTS) follow these steps:

- Install using official packages or from [LuaJIT](http://www.lua.org/) which is newer.

        sudo apt-get install luajit

- Build nginx with Lua support from official sources

        #register PGP keys
        wget --quiet -O - http://nginx.org/keys/nginx_signing.key | sudo apt-key add -

        #Create /etc/apt/sources.list.d/nginx.list with these entries
        deb http://ppa.launchpad.net/nginx/stable/ubuntu precise main
        deb-src http://ppa.launchpad.net/nginx/stable/ubuntu precise main

        #Run update apt lists
        sudo apt-get update

        #Create and go to directory for nginx source and compilation task, e.g. ~/mynginx
        sudo apt-get source nginx
        sudo apt-get build-dep nginx

        #Export LuaJIT paths.
        #Find them with `locate libluajit`

        export LUAJIT_LIB=/usr/lib/x86_64-linux-gnu
        export LUAJIT_INC=/usr/include/luajit-2.0

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
        # The important is to have word `jit`, without that it
        # means nginx will use base Lua interpreter, then check LUAJIT paths.

- Download `nginx-big-upload` files somewhere. Set up `$package_path` variable and `content_by_lua_file` directive to dowload location. Remember that all relative paths are relative to nginx config file.

- Optional: Ruby 2.0 is required to run tests from `test` directory, [RVM](https://rvm.io/rvm/install/) use is recommended.

## Configuration

### CRC32 checksum
Checksum of uploaded data can be provided by the client by `X-Checksum` request header. In case
of chunked upload that may be added in last chunk, because the header is passed to backend if Backend Handler is enabled.
Moreover Backend Handler puts `checksum` into backend request parameters.

To calculate checksum on server-side `$bu_checksum on;` configuration variable should be set. The server calculates
the checksum and Backend Handler includes it in the `checksum` param of backend request. If client provides 'X-Checksum'
then it is compared with server-side checksum. If they do not match a response code 400 is returned and further processing is stopped.

Server-side checksum with chunked upload requires client to pass partial checksums between chunks. This is because
server-side does not store any information to continue calculation of checksums for entire upload. The client
should remember the value of `X-Checksum` response header of last chunk and put it into `X-Last-Checksum` request header of next chunk.

Simplified example:

    > PUT /upload
    > Content-Range: bytes 0-4/10
    >
    > Part1
    < 201 Created
    < X-Checksum: 3053a846

    > PUT /upload
    > Content-Range: bytes 5-9/10
    > X-Last-Checksum: 3053a846
    >
    > Part2
    < 201 Created
    < X-Checksum: 478ac3e5

Client can also provide own `X-Checksum` in upload request then checksums will be matched:

    > PUT /upload
    > Content-Range: bytes 0-4/10
    > X-Checksum: 3053a846
    >
    > Part1
    < 201 Created
    < X-Checksum: 3053a846

    > PUT /upload
    > Content-Range: bytes 5-9/10
    > X-Last-Checksum: 3053a846
    > X-Checksum: 478ac3e5
    >
    > Part2
    < 201 Created
    < X-Checksum: 478ac3e5

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
* `nginx-upload-module` doesn't provide CRC32 calcullation in resumable mode.

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
    bu     51MB * 10  2.270000   2.760000   5.030000 ( 10.058877)  #nginx 1.4.1
    bu_crc 51MB * 10  2.190000   2.670000   4.860000 (  9.919086)  #nginx 1.4.1
    bu    204MB * 10  8.900000  10.410000  19.310000 ( 39.150926)  #nginx 1.4.1

## TODO:
* SHA1 calculation
* storage handler with back-end subrequest before first chunk - e.g. to check if upload is acceptable or to track temporary file
* upload status requests,
* back-end-side progress notifications,
* JavaScript example with HTML5 File API and file chunking with Blob.slice.
* cloud pass-thru upload handler,
* multiparts support - this is low priority please use excellent [nginx-upload-module](https://github.com/vkholodkov/nginx-upload-module/tree/2.2) or [lua-resty-upload](https://github.com/agentzh/lua-resty-upload)




