# nginx-big-upload

Written in Lua provides reliable uploads and easy to extend logic of file upload lifecycle.
Currently only PUT/POST RAW body resumable uploads are supported. These are compatible with [nginx-upload-module](https://github.com/vkholodkov/nginx-upload-module/tree/2.2) resumable
requests. This extension requires Nginx compiled with [HttpLuaModule](http://wiki.nginx.org/HttpLuaModule).

## Status

I started to write this project on 20th of March 2013.
The goal is to have it deployed on production system in mid-April,
For some form of documentation please see tests directory.


## nginx-big-upload vs nginx-upload-module

I created this module as an user of excellent `nginx-upload-module` which processed terabytes of data for several years. Sometimes I needed
more features which were missing such as CRC32 calculation for resumable uploads. Unfortunately I suspect that module may be abandoned, see [#41](https://github.com/vkholodkov/nginx-upload-module/issues/41),
therefore I started a development of new solution which will work with Nginx 1.3.8+ and will provide some area for enhancement. I prefer to use
Lua module which gives very short development/test iterations in reload per request mode. Here is Pros/Cons list of this module in comparison to `nginx-upload-module`:

* Pro: no status file because current offset is equal to size of linearly uploaded file;
* Pro: works with any version supported by Lua module including nginx 1.3.8+;
* Pro: this module supports the same resumable upload headers and response as `nginx-upload-module`, thus it may be drop-in replacement in some deployments;
* Pro: easy to enhance/fork, Lua modules are easy to develop, it took me 2 days to learn Lua and create this module;
* Cons: no multi-part POST format supported, only RAW file in PUT/POST request; check [lua-resty-upload](https://github.com/agentzh/lua-resty-upload);
* Cons: slightly slower because of Lua layer, but this is very small factor IMO, check the benchmark below;
* Cons/Pro: linear resumable - there is no way to upload last chunk as first in row, chunks must be uploaded sequentially; this is Pro actually because prevents DoS attacks with malicious upload request;
* Cons: no upload rate limit setting - only one client can upload a given file so it is better to throttle downloads.

### Benchmark

Below is the result of `test/performance_test.rb` method `test_final_perf`, which tests nginx-big-upload (bu) vs nginx-upload-module (num)
with chunked upload of identical data to the same backend. Each file is sent in ~512KB chunks which means 51MB file
is transferred in 100 requests. Times in seconds. Fileds user/system/total are rather related to test script execution times, but real is the real one.

                      user       system     total      real
    bu     51MB * 10  0.630000   0.820000   1.450000 (  3.199759)
    bu_crc 51MB * 10  0.670000   0.910000   1.580000 (  4.164285)
    num    51MB * 10  0.680000   0.920000   1.600000 (  2.677721)
    bu    204MB * 10  2.520000   3.510000   6.030000 ( 12.576817)
    num   204MB * 10  2.480000   3.940000   6.420000 ( 10.818588)

## Prerequisites

* Nginx with Lua module built in. LuaJIT is preferred as runtime implementation. Hint: run `ldd nginx` to make sure LuaJIT will be used.
* To run tests you also need nginx with [nginx-upload-module v2.2](https://github.com/vkholodkov/nginx-upload-module/tree/2.2) and Ruby 2.0, but 1.9.x may also work.

## Features

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

## TODO:
* storage handler with back-end subrequest before first chunk - e.g. to check if upload is acceptable or to track temporary file
* upload status requests,
* back-end-side progress notifications,
* JavaScript example with HTML5 File API and file chunking with Blob.slice.
* cloud pass-thru upload handler,
* multiparts support - this is low priority please use excellent [nginx-upload-module](https://github.com/vkholodkov/nginx-upload-module/tree/2.2) or [lua-resty-upload](https://github.com/agentzh/lua-resty-upload)




