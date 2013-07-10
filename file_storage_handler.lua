-- Copyright (C) 2013 Piotr Gaertig

-- Naive file storage implementation for each valid chunk status code "201 Created" is returned.
-- Upload module has no contact with a backend. The client uploading the file should call the backend
-- after successfully submitting last chunk of file. Then the backend should look for file named as
-- Session-ID in the upload directory.


local setmetatable = setmetatable
local concat = table.concat
local io = io
local string = string
local error = error
local ngx = ngx

module(...)

-- local mt = { __index = _M }


local function init_file(self, ctx)
  local file_path = ctx.file_path
  local file
  if not ctx.first_chunk then
    -- file must exist for follow up chunks
    file = io.open(file_path, 'r+')  -- Open file for update (reading and writing).
    if not file then
      -- no file with preceding chunks, report we got nothing so far
      return {409, "0-0/0"}
    end
    local size = file:seek("end")
    if size < ctx.range_from then
        -- missing chunk? return what we have got so far
        file:close()
        return {409, string.format("0-%d/%d", size - 1, ctx.range_total) }
    end

    -- requests may be resend with same chunk
    if size ~= ctx.range_from then
        file:seek("set", ctx.range_from)
    end
  else
    -- write from scratch
    file = io.open(ctx.file_path, "w") -- Truncate to zero length or create file for writing.
  end

  if not file then
    return concat({"Failed to open file ", file_path})
  end
  self.file = file
end

local function close_file(self)
  if self.file then
    self.file:close()
  end
end

local function on_body_start(self, ctx)
  ctx.file_path = concat({self.dir, ctx.id}, "/")
  return self:init_file(ctx)
end

local function on_abort(self)
  self:close_file()
end

-- writes body data
local function on_body(self, ctx, body)
  if self.file then
    self.file:write(body)
  end
end

local function on_body_end(self, ctx)
  close_file(self)
  -- return what what we have on server
  return {201, string.format("0-%d/%d", ctx.range_to, ctx.range_total) }
end


function _M:new(dir)
    return setmetatable({
       dir = dir or '/tmp',
       file = nil,

       -- interface functions
       on_body = on_body,
       on_body_start = on_body_start,
       on_body_end = on_body_end,

       -- other functions
       init_file = init_file,
       close_file = close_file
    }, _M)
end


setmetatable(_M, {
  __newindex = function (_, n)
    error("attempt to write to undeclared variable "..n, 2)
  end,
  __index = function (_, n)
    error("attempt to read undeclared variable "..n, 2)
  end,
})
