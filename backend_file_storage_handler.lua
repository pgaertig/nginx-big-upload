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


module(...)

local function end_backend(self)
  local pc = self.payload_context;
  -- last chunk commited?
  if pc.range_to + 1 == pc.range_total then
    return ngx.location.capture(self.backend, { body =
        ngx.encode_args({
          size = pc.range_total,
          id = self.id,
          path = self.file_path,
          name = pc.get_name()
        })
    })
  end
end

-- overriden
local function on_body_start(self, id, payload_context)
  self.id = id
  self.payload_context = payload_context
  local file_path = concat({self.dir, id}, "/")
  self.file_path = file_path
  return self:init_file()
end

-- overriden
local function on_body_end(self)
  self:close_file()
  -- call backend if finished
  local res = end_backend(self)
  local pc = self.payload_context
  return {201, string.format("0-%d/%d", pc.range_to, pc.range_total), response = res }
end


function _M:new(dir, backend)
    if not backend then
      return nil, "Configuration error: no backend specified"
    end
    local inst = {
        super = file_storage_handler:new(dir),
        backend = backend,
        on_body_start = on_body_start,
        on_body_end = on_body_end,
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