-- Copyright (C) 2013 Piotr Gaertig

local concat = table.concat
local match = string.match
local setmetatable = setmetatable
local tonumber = tonumber
local error = error
local print = print
local string = string
local math = math
local ngx = ngx
local type = type
local ipairs = ipairs
local crc32 = crc32
local sha1_handler = sha1_handler
local io = io
local util = require('util')


module(...)

local mt = { __index = _M }

_M.chunk_size = 4096
_M.socket_timeout = 30000

local function raw_body_by_chunk(self)
    if self.left == 0 then
       return nil
    end

    local current_chunk_size = self.left < self.chunk_size and self.left or self.chunk_size
    -- local current_chunk_size = math.min(self.left,self.chunk_size)
    self.left = self.left - current_chunk_size
    local chunk, err =  self.socket:receive(current_chunk_size)
    if err then
        return nil, "Socket receive error: "..err
    end

    return chunk
end



-- Checks request headers and creates upload context instance
function new(self, handlers)
    local ctx = {}
    local headers = ngx.req.get_headers()

    local content_length = tonumber(headers["content-length"])
    if not content_length then
      return nil, {411, "Content-Length missing"}
    end
    if content_length < 0 then
      return nil, {411, "Negative content length"}
    end

    local range_from, range_to, range_total
    local content_range = headers["content-range"] or headers["x-content-range"]
    if content_range then
      range_from, range_to, range_total = content_range:match("%s*bytes%s+(%d+)-(%d+)/(%d+)")
      if not (range_from and range_to and range_total) then
        return nil, {412, string.format("Invalid Content-Range format, was: %s", content_range)}
      end
      range_from = tonumber(range_from)
      range_to = tonumber(range_to)
      range_total = tonumber(range_total)
    else
      -- no resumable upload but keep range info for handlers
      range_from = 0
      range_to = math.max(content_length-1, 0)  -- CL=0 -> 0-0/0
      range_total = content_length
    end

    if range_from == 0 then
      ctx.first_chunk = true
    end

    local session_id = headers["session-id"] or headers["x-session-id"]
    if not session_id then
        if not ctx.first_chunk then
            return nil, {412, "Session-id is required for chunked upload." }
        else
            session_id = util.random_sha1()
        end
    else
        if session_id:match('%W') then
            return nil, {412, string.format("Session-id is invalid only alphanumeric value are accepted, was %s", session_id)}
        end
    end

    ctx.range_from = range_from
    ctx.range_to = range_to
    ctx.range_total = range_total
    ctx.content_length = content_length

    -- 0-0/0 means empty file 0-0/1 means one byte file, paradox but works
    if range_from == 0 and range_to == 0 and range_total == 0 then
      if content_length ~= 0 then
        return nil, {412, "Range is zero but Content-Length is non zero"}
      end
    else
      -- some more weird range tests

      -- these should fail: 3-2/4 or 0-4/4
      if range_from > range_to or range_to > range_total-1 then
        return nil, {412, string.format("Range data invalid %d-%d/%d", range_to, range_from, range_total)}
      end

      --
      if content_length-1 ~= range_to - range_from then
        return nil, {412, string.format("Range size does not match Content-Length (%d-%d/%d vs %d)", range_to, range_from, range_total, content_length)}
      end
    end

    if not handlers or #handlers == 0 then
      return nil, "Configuration error: no handlers defined"
    end

    -- Name can be send with each chunk but it is really needed for the last one.
    ctx.get_name = function()
      local content_disposition = headers['Content-Disposition']
      if type(content_disposition) == "table" then
        -- Opera attaches second header on xhr.send - first one is ours
        content_disposition = content_disposition[1]
      end
      if content_disposition then
        -- http://greenbytes.de/tech/webdav/rfc5987.html
        local mname = string.match(
            content_disposition, "%s*%w+%s*;%s*%w+%s*=%s*\"?([^\"]+)")
          or string.match(
            content_disposition, "%s*%w+%s*;%s*%w+%*%s*=%s*UTF%-8''(.+)")  -- eventual UTF8 case
        if mname then
          return mname
        end
        ngx.log(ngx.WARN, "Couldn't extract file name from Content-Disposition:"..content_disposition)
      end
    end

    local last_checksum = headers['X-Last-Checksum'] -- checksum of last server-side chunk
    if last_checksum then
      if not crc32.validhex(last_checksum) then
        return nil, {400, "Bad X-Last-Checksum format: " .. last_checksum}
      end
      ctx.last_checksum = last_checksum
    end

    local checksum = headers['X-Checksum'] -- checksum from beginning of file up to current chunk
    if checksum then
      if not crc32.validhex(checksum) then
        return nil, {400, "Bad X-Checksum format: " .. checksum}
      end
      ctx.checksum = checksum
    end

    local xsha1 = headers['X-SHA1'] -- checksum from beginning of file up to current chunk
    if xsha1 then
      if not sha1_handler.validhex(xsha1) then
        return nil, {400, "Bad X-SHA1 format: " .. xsha1}
      end
      ctx.sha1 = xsha1
    end


    local socket

    -- prevent 'no body' error on empty request
    if content_length ~= 0 then
       local sk, err = ngx.req.socket()
       if not sk then
         return nil, {500, err, concat({"Socket error: ", err})}
       end
       sk:settimeout(socket_timeout)
       socket = sk
    end

    ctx.id = session_id

    return setmetatable({
        socket = socket,
        chunk_size = chunk_size,
        content_length = content_length,
        left = content_length,
        session_id = session_id,
        handlers = handlers,
        payload_context = ctx
    }, mt)
end

local function prepopulate_response_headers(ctx)
    ngx.header['X-Session-Id'] = ctx.id
end

function process(self)
    prepopulate_response_headers(self.payload_context)

    for i, h in ipairs(self.handlers) do
      local result = h.on_body_start and h:on_body_start(self.payload_context)
      if result then return result end  -- something important happened to stop upload
    end

    -- internally this loop is non-blocking
    while true do
      local chunk, err = raw_body_by_chunk(self)
      if not chunk then
        if err then
            for i, h in ipairs(self.handlers) do
                if h.on_abort then h:on_abort() end
            end
            return err
        end
        break
      end
      for i, h in ipairs(self.handlers) do
        local result = h.on_body and h:on_body(self.payload_context, chunk)
        if result then return result end
      end
    end

    for i, h in ipairs(self.handlers) do
      local result = h.on_body_end and h:on_body_end(self.payload_context)
      if result then return result end
    end
end

setmetatable(_M, {
  __newindex = function (_, n)
    error("attempt to write to undeclared variable "..n, 2)
  end,
  __index = function (_, n)
    error("attempt to read undeclared variable "..n, 2)
  end,
})

