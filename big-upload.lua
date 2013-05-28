-- Main nginx-big-upload file which is specified in nginx config files.
-- Copyright (C) 2013 Piotr Gaertig

local config = {
    package_path = ngx.var.package_path,
    bu_checksum = ('on' ==  ngx.var.bu_checksum),
    bu_sha1 = ('on' == ngx.var.bu_sha1)
}

if config.package_path then
    package.path = config.package_path .. ";" .. package.path
end

local file_storage_handler = require "file_storage_handler"
local backend_file_storage_handler = require "backend_file_storage_handler"
local crc32 = require('crc32')
local sha1= require('sha1_handler')

local function report_result(info)
  if type(info) == "table" then
    if info.response then
      -- response from backends
      res = info.response
      ngx.status = res.status
      for k, v in pairs(res.header) do
        ngx.header[k] = v
      end
      ngx.print(res.body)
      return ngx.OK
    else
      -- expected errors and statuses
      ngx.status = info[1]
      ngx.print(info[2])
      if info[3] then
        ngx.log(ngx.ERR, info[3])
      end
      return ngx.OK
    end
  else
    -- unexpected errors, output to error log and 500
    ngx.log(ngx.ERR, info)
    ngx.status = 500
    return ngx.ERROR
  end
end

local reqp = require "request_processor"
local err
local handlers = {}
local storage_handler
if ngx.var.storage == 'backend_file' then
  if not ngx.var.backend_url then
    return report_result("$backend_url is not defined")
  end
  storage_handler, err = backend_file_storage_handler:new(ngx.var.file_storage_path, ngx.var.backend_url)
else
  storage_handler, err = file_storage_handler:new(ngx.var.file_storage_path)
end


if config.bu_checksum then
  table.insert(handlers, crc32.handler())
end
if config.bu_sha1 then
 table.insert(handlers, sha1.handler(ngx.var.file_storage_path))
end
table.insert(handlers, storage_handler)

if err then
  return report_result(err)
end

local ctx, err = reqp:new(handlers)
return report_result(err or ctx:process())

