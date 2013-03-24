# nginx-big-upload

Written in Lua provides reliable uploads and easy to extend logic of file upload lifecycle.
Currently only PUT/POST RAW body resumable uploads are supported. These are compatible with [nginx-upload-module](https://github.com/vkholodkov/nginx-upload-module/tree/2.2) resumable
requests. This extension requires Nginx compiled with (HttpLuaModule)[http://wiki.nginx.org/HttpLuaModule].

## Status

I started to write this project on 20th of March 2013 and I am currently testing it in development environment.
The goal is to have it deployed on production system in mid-April, shoud serve

For some form of documentation please see tests directory.

## TODO:
* upload status requests,
* backend-side progress notifications,
* CRC32,
* JavaScript example with HTML5 File API and file chunking with Blob.slice.
* cloud pass-thru upload handler,
* multiparts support - this is low priority please use excellent [nginx-upload-module](https://github.com/vkholodkov/nginx-upload-module/tree/2.2) or [lua-resty-upload](https://github.com/agentzh/lua-resty-upload)


