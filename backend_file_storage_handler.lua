-- Copyright (C) 2013 Piotr Gaertig

-- Same as file_storage_handler but communicates with backend on file start and file end.
-- Result from file start is returned when backend returns status code greater than 299.
-- In case of file end the result from backend call is always returned.

local file_storage_handler = require "file_storage_handler"
local setmetatable = setmetatable
local ngx = ngx
local string = string
local concat = table.concat
local error = error
local os = os

module(...)

local function end_backend(self, ctx)
  -- last chunk commited?
  if ctx.range_to + 1 == ctx.range_total then

    -- seed body arguments into table..
    local body_args = {
            size = ctx.range_total,
            id = ctx.id,
            path = ctx.file_path,
            name = ctx.get_name(),
            file_name = ctx.file_name,
            checksum = ctx.checksum,
            sha1 = ctx.sha1
    }

    -- parameterize misc value if populated..
    -- note: misc must be a string of uri-style parameters. i.e. a=1&b=2
    -- fucking nginx strips inbound complex key->value tables into simple string arrays
    if ctx.misc ~= nil then
      for kv in string.gmatch(ctx.misc, "[^&]+") do
        for k, v in string.gmatch(kv, "(%w.+)=(%w.+)") do
          body_args[k] = v
        end
      end
    end

    ngx.req.set_header('Content-Type', 'application/x-www-form-urlencoded')
    return ngx.location.capture(self.backend, {
        method = ngx.HTTP_POST,
        body = ngx.encode_args(body_args)
    })
  end
end

local function move_file(self, ctx)
  if ctx.file_path and ctx.success_destination_dir then
    local ret, err = os.rename(ctx.file_path, concat({ctx.success_destination_dir, ctx.file_name}, "/"))
    if ret == nil or err ~= nil then
      return string.format("Failed to move completed file: %s to: %s. Error: %s", ctx.file_path, ctx.success_destination_dir, err)
    end
  end
end

-- override
local function on_body_start(self, ctx)
  local file_path = concat({self.dir, ctx.id}, "/")
  if ctx.file_name ~= nil then
    -- use explicitly specified filename..
    file_path = concat({self.dir, ctx.file_name}, "/")
  end
  ctx.file_path = file_path
  return self:init_file(ctx)
end

-- override
local function on_body_end(self, ctx)
  self:close_file()
  if ctx.range_to + 1 == ctx.range_total then
    local ret = move_file(self, ctx)
    if ret then
      ngx.log(ngx.ERR, ret)
      return ngx.ERROR
    end
  end
  -- call backend if finished & move successful
  local res = end_backend(self, ctx)
  return {201, string.format("0-%d/%d", ctx.range_to, ctx.range_total), response = res }
end


function _M:new(dir, backend)
    if not backend then
      return nil, "Configuration error: no backend specified"
    end
    local inst = {
        super = file_storage_handler:new(dir),
        backend = backend,
        on_body_start = on_body_start,
        on_body_end = on_body_end
    }
    return setmetatable(inst, { __index = function(t,k) return t.super[k] end} )
end


setmetatable(_M, {
  __newindex = function (_, n)
    error("attempt to write to undeclared variable "..n, 2)
  end,
  __index = function (_, n)
    error("attempt to read undeclared variable "..n, 2)
  end,
})