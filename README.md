# nginx-big-upload

Written in Lua provides reliable uploads and easy to extend logic of file upload lifecycle.
Currently only PUT/POST RAW body resumable uploads are supported. These are compatible with [nginx-upload-module](https://github.com/vkholodkov/nginx-upload-module/tree/2.2) resumable
requests. This extension requires Nginx compiled with [HttpLuaModule](http://wiki.nginx.org/HttpLuaModule).

## Status

I started to write this project on 20th of March 2013 and I am currently testing it in development environment.
The goal is to have it deployed on production system in mid-April,
For some form of documentation please see tests directory.


## nginx-big-upload vs nginx-upload-module

I created this module as an user of excellent `nginx-upload-module` which processed many terabytes of data for several years. Sometimes I needed
more features which were missing such as CRC32 calculation for resumable uploads. Unfortunately recently I realized that module may be abandoned, see [#41](https://github.com/vkholodkov/nginx-upload-module/issues/41),
therefore I started a development of new solution which will compile with Nginx 1.3.8+ and will provide some area for enhancement. I preferred to use
Lua module which gives very short development/test iterations in reload per request mode. Here is Pros/Cons list of this module in comparison to `nginx-upload-module`:

* Pro: no status file because current offset is equal to size of linearly uploaded file;
* Pro: works with any version supported by Lua module including nginx 1.3.8+;
* Pro: this module supports the same resumable upload headers and response as `nginx-upload-module`, thus it may be drop-in replacement in some deployments;
* Pro: easy to enhance/fork, Lua modules are easy to develop, it took me 2 days to learn Lua and create this module;
* Cons: no multi-part POST format supported, only RAW file in PUT/POST request; check [lua-resty-upload](https://github.com/agentzh/lua-resty-upload);
* Cons: slightly slower because of Lua layer, but this is very small factor IMO, check the benchmark below;
* Cons/Pro: linear resumable - there is no way to upload last chunk as first in row, chunks must be uploaded sequentially; this is Pro actually because prevents DoS attacks with malicious upload request;
* Cons: no upload rate limit setting - I don't see a need for it - only one client can upload a given file so it is better to throttle downloads

### Benchmark

Below is the result of `test/performance_test.rb` method `test_final_perf`, which tests nginx-big-upload (lua) vs nginx-upload-module (num)
with chunked upload of identical data to the same backend. Each file is sent in ~512KB chunks which means 51MB file
is transferred in 100 requests. Times in seconds. Fileds user/system/total are rather related to test script execution times, but real is the real one.

                          user       system     total     real
    lua 51MB * 10 files   0.730000   0.780000   1.510000  (  3.244294)
    num 51MB * 10 files   0.720000   0.910000   1.630000  (  2.662686)
    lua 204MB * 10 files  3.030000   3.730000   6.760000  ( 12.659967)
    num 204MB * 10 files  2.670000   3.670000   6.340000  ( 10.785138)

## Prerequisites

* Nginx with Lua module built in. LuaJIT is preferred as runtime implementation. Hint: check if LuaJIT is used with `ldd nginx`.
* To run tests you also need nginx with [nginx-upload-module v2.2](https://github.com/vkholodkov/nginx-upload-module/tree/2.2) and Ruby 2.0, but may work with earlier versions.

## TODO:
* storage handler with back-end subrequest before first chunk - e.g. to check if upload is acceptable or to track temporary file
* upload status requests,
* back-end-side progress notifications,
* CRC32,
* JavaScript example with HTML5 File API and file chunking with Blob.slice.
* cloud pass-thru upload handler,
* multiparts support - this is low priority please use excellent [nginx-upload-module](https://github.com/vkholodkov/nginx-upload-module/tree/2.2) or [lua-resty-upload](https://github.com/agentzh/lua-resty-upload)




