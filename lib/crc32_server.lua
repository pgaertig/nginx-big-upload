-- Copyright (C) 2017 Piotr Gaertig
-- CRC32 checksum function handler for nginx-big-upload pipeline
-- Checksum state is persisted on the server-side in .crc32 files

local tonumber = tonumber
local string = string
local ngx = ngx
local table = table
local io = io
local assert = assert
local concat = table.concat
local util = require('util')
local crc32 = require('crc32')

module(...)

local function crc32h_to_file(file_path, hex_checksum, offset)
  local out = assert(io.open(file_path .. '.crc32', "wb"))
  out:write(offset)
  out:write("\n")
  out:write(hex_checksum)
  assert(out:close())
end

local function crc32_from_file(file_path)
  local inp = io.open(file_path .. '.crc32', "rb")
  if inp then
    local offset = tonumber(inp:read("*line"))
    local checksum = tonumber(inp:read("*all"), 16)
    assert(inp:close())
    return offset, checksum
  end
  return
end


function handler(storage_path)
  return {
    on_body_start = function(self, ctx)
      self.skip_bytes = 0
      self.file_path = concat({ storage_path, ctx.id }, "/")
      if ctx.first_chunk then
        self.current_checksum = 0
      else
        self.real_size, self.current_checksum = crc32_from_file(self.file_path)

        --overlapping chunk upload, need to skip repeated data
        self.skip_bytes = self.real_size - ctx.range_from
        return
      end
    end,

    on_body = function(self, ctx, body)
      if self.skip_bytes > 0 then
        -- skip overlaping bytes
        if self.skip_bytes > #body then
          -- skip this entire body part
          self.skip_bytes = self.skip_bytes - #body
          return
        else
          body = body:sub(self.skip_bytes + 1)
          self.skip_bytes = 0
        end
      end
      if body and #body > 0 then
        self.current_checksum = crc32.crc32(body, self.current_checksum)
      end
    end,

    on_body_end = function(self, ctx)
      if self.skip_bytes == 0 then
        self.real_size = ctx.range_from + ctx.content_length
        local hex_checksum = crc32.tohex(self.current_checksum)
        crc32h_to_file(self.file_path, hex_checksum, self.real_size)

        -- validate client provided checksum
        if ctx.checksum and (tonumber(ctx.checksum,16) ~= self.current_checksum) then
          return {400, string.format("Chunk checksum mismatch client=[%s] server=[%s]", ctx.checksum, hex_checksum)}
        end
        ctx.checksum = hex_checksum
        ngx.header['X-Checksum'] = hex_checksum
      end
    end
  }
end
