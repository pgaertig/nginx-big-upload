# nginx-big-upload

Reliable RAW PUT/POST uploads and easy to extend Lua logic of file upload lifecycle.

## Features

- PUT/POST RAW uploads;
- Partial chunked and resumable uploads;
- On the fly resumable CRC32 checksum calculation with client-side or server-side state;
- On the fly resumable SHA-1 with server-side state;
- [nginx-upload-module](https://github.com/vkholodkov/nginx-upload-module/tree/2.2) resumable protocol compatibility;
- Easy to enhance/fork with Lua and fast asynchronous Lua module API;
- Unlimited file size, tested with 1TB files;
- Several years under production load on sponsor projects. 

## Runtime prerequisites

The following perquisites Above are available as standard packages in Debian 8+ and Ubuntu 16.04+, please see `examples/test-*/` directories which
contain setup scripts for various use cases. Docker is not required as it is used to isolate test environments.
 
 - Nginx 1.x with Lua support enabled,
 - LuaJIT,
 - Shared library: libcrypto.so version 1.0.2 for SHA1 and SHA256 calculation
 - Shared library: libz.so (Zlib) needed for CRC32 calculation

### Docker image

This module is also available as Docker image bundled with statically compiled Nginx with LuaJIT and configuration autoreload.
It has also [mod_zip](https://github.com/evanmiller/mod_zip) 3rd party module compiled in. *mod_zip* can generate on-the-fly ZIP archives from uploaded files. The interesting feature of *mod_zip* is that
it can resume ZIP downloads once CRC32 of each archive file is provided by a backend. See more details on mod_zip's README.

You can try the image locally for development or test with `simple_upload` and `test-dockerfile-nginx` examples.
 
*TODO describe docker image usage and params*

## Configuration

To use this module first you need to copy the the project into some directory, e.g.
    
    git clone -b v1.2.2 https://github.com/pgaertig/nginx-big-upload.git /opt/nginx-big-upload
    
Please check the available git tags to pin to the latest project version. The master branch may have breaking changes introduced in the future.      
    
**Important:** Nginx worker process user or group needs read-only access rights to all lua files in`/opt/nginx-big-upload/lib/` directory. The user and group of nginx worker proces is defined by [user](http://nginx.org/en/docs/ngx_core_module.html#user) directive.
    
Below is example upload configuration in nginx configuration file. There is more examples in `examples/simple_upload/nginx.conf` and `test/nginx-big-upload-test.conf`. 

    lua_package_path "/opt/nginx-big-upload/lib/?.lua;;"; 
    server {  
    ...
        location = /upload {
          set $storage backend_file;
          set $file_storage_path /tmp;
          set $backend_url /files/add;
    
          set $bu_sha1 on;
          set $bu_sha256 on;
          set $bu_checksum on;
    
          content_by_lua_file /opt/nginx-big-upload/big-upload.lua;
        }
    ....
    }

### set $storage backend_file | file;

With `file` the uploaded file is just saved to disk under `$file_storage_path` directory. Every successfully uploaded chunk request responds with HTTP code `201 Created`.
The `backend_file` works same as `file` except successful upload of last chunk invokes the backend specified in `$backend_url`, see below.

### set $file_storage_path *directory_path*;
This variable should contain path where the uploaded files will be stored. File names same as `X-Session-Id` header value sent by the client. For the security the header value can only contain
alphanumeric characters (0-9,a-z,A-Z). The `X-Session-Id` is also returned in response of every successful chunk upload. Additionaly the response body of each chunk shows current range of file uploaded so far, e.g. `0-4095/1243233`.
**Important:** Nginx's worker user or group needs read-write access rights to the directory. Files saved there will have the same owner and group assigned as the worker process.

### set $backend_url *url*;
This variable contains a location which will be invoked when file upload is complete on the server. This is only done when backend handler is enabled by `$storage backend_file;`.
The request sent to backend will be POST request with url-encoded body params:

* `id` - identifier of file, sent in `X-Session-ID`;
* `name` - name of file extracted from `Content-disposition` request header;
* `path` - server-side path to uploaded file;
* `checksum` - optional CRC32 checksum - see `$bu_checksum` setting;
* `sha1` - optional SHA-1 hex string - see `$bu_sha1` setting;
* `sha256` - optional SHA-256 hex string -see `$bu_sha256` setting;

The `url` value should refer to location recognized in nginx configuration. Outbound absolute HTTP/HTTPS URLs were not tested yet. Remember to declare a backend location with `internal;` nginx directive to prevent external access to the backend endpoint.
 
 Named locations are not supported with `$backend_url`, e.g. `@rails_app`, but there is simple workaround for it:

    location /files/add {
     internal;
     access_log off;
     content_by_lua 'ngx.exec("@rails_app")';
    }

With the above example the last chunk's success request processing will be forwarded to `@rails_app` named location.


### set $bu_sha1 on | off
This variable enables on-the-fly hash calculation of SHA-1 on uploaded content. The result will be returned to client in `X-SHA1` header as hexadecimal string.
Client can provide `X-SHA1` header in request so then server will verify it on the end of each chunk.
If resumable upload is performed then both headers should contain hash of data uploaded so far and both are compared on the end of each chunk.
For security reasons SHA-1 context in between chunks is stored on the server in the same path as uploaded file plus additional `.shactx` extension.
Using client-side state as with CRC32 checksum calculation is not possible.

### set $bu_sha256 on | off
This variable enables on-the-fly hash calculation of SHA-256 on uploaded content. The result will be returned to client in `X-SHA256` header as hexadecimal string.
Client can provide `X-SHA256` header in request so then server will verify it on the end of each chunk.
If resumable upload is performed then both headers should contain hash of data uploaded so far and both are compared on the end of each chunk.
For security reasons SHA-256 context in between chunks is stored on the server in the same path as uploaded file plus additional `.sha256ctx` extension.
Using client-side state as with CRC32 checksum calculation is not possible.

### set $bu_checksum on|server|off
This option enables CRC32 calculation. If `on` turns on validation on server-side with state saved on client side in case of chunked upload. The value `server` turns on validation and state saved on server-side only. State files are stored in the same place where uploaded files but with `.crc32` suffix.

#### CRC32 Verification

The server returns `X-Checksum` header for entire content already uploaded whatever it is single request or chunked upload. The client optionally can send its own calculated `X-Checksum` header in the request. Then server will compare both checksums and fail in case of mismatch.

#### Resumable CRC32 state

In case of `$bu_checksum on` the server is not storing the state of CRC32 calculation when chunked upload is performed.
In such case the client needs to keep that state. For every chunk except the first one
the client should pass the value of previous chunk's response header `X-Checksum` as request header `X-Last-Checksum`. See example conversation in following sections or scripts in `test/` directory.

## Example client-server conversation with resumable upload and client-side CRC32 state

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

## Known limitations

- HTTP/2 not yet supported (limitation of nginx/lua module)
- No upload rate limit setting - only one client can upload a given file so it is better to throttle downloads.
- Multi-part POST requests from web forms are not supported as resumability logic would be quite complex, please use [lua-resty-upload](https://github.com/agentzh/lua-resty-upload) instead.
- Chunks must be uploaded sequentially - this prevents race conditions and bomb file DoS attacks (e.g. starting with last chunk of 1TB file). 


## TODO:
* describe protocol;
* storage handler with back-end sub-request before the first chunk - e.g. to check if upload is acceptable or to track temporary file growth/timestamp;
* upload status requests - would provide resumability for failed single part uploads;
* compile *.lua into LuaJIT byte-code (test perf);




