# nginx-big-upload

Written in Lua provides reliable uploads and easy to extend logic of file upload lifecycle.
Currently only PUT/POST RAW body resumable uploads are supported. These are compatible with [nginx-upload-module](https://github.com/vkholodkov/nginx-upload-module/tree/2.2) resumable
requests. This extension requires Nginx compiled with [HttpLuaModule](http://wiki.nginx.org/HttpLuaModule).

## Status

I started to write this project on 20th of March 2013 and I am currently testing it in development environment.
The goal is to have it deployed on production system in mid-April,

For some form of documentation please see tests directory.

## TODO:
* upload status requests,
* backend-side progress notifications,
* CRC32,
* JavaScript example with HTML5 File API and file chunking with Blob.slice.
* cloud pass-thru upload handler,
* multiparts support - this is low priority please use excellent [nginx-upload-module](https://github.com/vkholodkov/nginx-upload-module/tree/2.2) or [lua-resty-upload](https://github.com/agentzh/lua-resty-upload)


## Benchmark

Below is the result of `test/performance_test.rb` method `test_final_perf`, which tests nginx-big-upload (lua) vs nginx-upload-module (num)
with chunked upload of identical data to the same backend. Each file is sent in ~512KB chunks which means 51MB file
is transferred in 100 requests. Times in seconds, user/system/total are rather related to test script execution times, but real is the real one.

                          user       system     total     real
    lua 51MB * 10 files   0.730000   0.780000   1.510000  (  3.244294)
    num 51MB * 10 files   0.720000   0.910000   1.630000  (  2.662686)
    lua 204MB * 10 files  3.030000   3.730000   6.760000  ( 12.659967)
    num 204MB * 10 files  2.670000   3.670000   6.340000  ( 10.785138)

