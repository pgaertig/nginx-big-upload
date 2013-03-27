-- Copyright (C) 2013 Piotr Gaertig

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
local storage_handler
if ngx.var.storage == 'backend_file' then
  local storage_handler_meta = require "backend_file_storage_handler"
  if not ngx.var.backend_url then
    return report_result("$backend_url is not defined")
  end
  storage_handler, err = storage_handler_meta:new(ngx.var.file_storage_path, ngx.var.backend_url)
else
  local storage_handler_meta = require "file_storage_handler"
  storage_handler, err = storage_handler_meta:new(ngx.var.file_storage_path)
end

if err then
  return report_result(err)
end

local ctx, err = reqp:new(storage_handler)



-- ngx.req.clear_header("Accept-Encoding");
return report_result(err or ctx:process())

