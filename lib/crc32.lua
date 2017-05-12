-- Copyright (C) 2013 Piotr Gaertig

-- CRC32 checksum

local ffi = require('ffi')
local tonumber = tonumber
local string = string
local ngx = ngx
local table = table

module(...)

local zlib = ffi.load('z')
ffi.cdef[[
    unsigned long crc32(unsigned long crc, const char *buf, unsigned len );
]]

function crc32(data, lastnum)
  return tonumber(zlib.crc32(lastnum, data, #data))
end

function validhex(crchex) return #crchex <= 8 and string.match(crchex, "^%x+$") end
function tohex(crcnum) return string.format("%08.8x", crcnum) end

function crc32hex(data, last)
  local lastnum = last and tonumber(last, 16) or 0
  local currnum = crc32(data,lastnum)
  return tohex(tonumber(currnum))
end

function handler()
  return {
    on_body_start = function (self, ctx)
      ctx.current_checksum = ctx.last_checksum and tonumber(ctx.last_checksum, 16) or ( ctx.first_chunk and 0 )
      -- stop checksum processing if X-Last-Checksum is not present for non first chunk
      if not ctx.current_checksum then
        self.on_body = nil
        self.on_body_end = nil
      end
    end,

    on_body = function (self, ctx, body)
      ctx.current_checksum = crc32(body, ctx.current_checksum)
    end,

    on_body_end = function (self, ctx)
      if ctx.checksum then
        if tonumber(ctx.checksum,16) ~= ctx.current_checksum then
          return {400, string.format("Chunk checksum mismatch client=[%s] server=[%s]", ctx.checksum, tohex(ctx.current_checksum))}
        end
      else
        ctx.checksum = tohex(ctx.current_checksum)
      end
      if ctx.checksum then ngx.header['X-Checksum'] = ctx.checksum end
    end
  }
end