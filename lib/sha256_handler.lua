-- Copyright (C) 2013 Piotr Gaertig
-- Copyright (C) 2019 Martin Matuska
-- SHA256 shortcut function handler for nginx-big-upload pipeline
-- This is stateless handler, it saves .sha256 file with SHA256 context data.

local ffi = require('ffi')
local tonumber = tonumber
local string = string
local ngx = ngx
local table = table
local io = io
local assert = assert
local concat = table.concat
local util = require('util')

local function validhex(sha256hex) return #sha256hex <= 64 and string.match(sha256hex, "^%x+$") end

local crypto = ffi.load('crypto')

-- extracted from https://github.com/openssl/openssl/blob/master/include/openssl/sha.h
ffi.cdef[[

  typedef struct SHA256state_st
  {
	    unsigned int h[8];
	    unsigned int Nl,Nh;
	    unsigned int data[16];
	    unsigned int num, md_len;
  } SHA256_CTX; //112 bytes

  int SHA256_Init(SHA256_CTX *shactx);
  int SHA256_Update(SHA256_CTX *shactx, const void *data, unsigned long len);
  int SHA256_Final(unsigned char *md, SHA256_CTX *shactx);
]]

local function shactx_to_file(file_path, shactx, offset)
  local out = assert(io.open(file_path..'.sha256ctx', "wb"))
  local binctx = ffi.string(shactx, 112)
  out:write(offset)
  out:write("\n")
  out:write(binctx)
  assert(out:close())
end

local function shactx_from_file(file_path)
  local inp = io.open(file_path..'.sha256ctx', "rb")
  if inp then
    file_size = tonumber(inp:read("*line"))
    file_data = inp:read("*all")
    assert(inp:close())
    -- ffi.copy(file_data, shactx, 112)
    return file_size, ffi.cast("SHA256_CTX*", file_data)
  end
  return
end


local function handler(storage_path)
  return {

    on_body_start = function (self, ctx)
      self.sha256_ctx = ffi.new("SHA256_CTX")
      self.skip_bytes = 0
      if not ctx.first_chunk then
        local file_path = concat({storage_path, ctx.id}, "/")  -- file based backends not initialized yet
        self.real_size, self.sha256_ctx = shactx_from_file(file_path)

        --overlapping chunk upload, need to skip repeated data
        self.skip_bytes = self.real_size - ctx.range_from
        return
      end
      if crypto.SHA256_Init(self.sha256_ctx) == 0 then
        return string.format("SHA256 initialization failed")
      end
    end,

    on_body = function (self, ctx, body)
      if self.skip_bytes > 0 then
        -- skip overlaping bytes
        if self.skip_bytes > #body then
          -- skip this entire body part
          self.skip_bytes = self.skip_bytes - #body
          return
        else
          body = body:sub(self.skip_bytes+1)
          self.skip_bytes = 0
        end
      end
      if body and #body > 0 then
        if crypto.SHA256_Update(self.sha256_ctx, body, #body) == 0 then
          return string.format("SHA256 update failed")
        end
      end
    end,

    on_body_end = function (self, ctx)
      if self.skip_bytes == 0 then
        -- In overlapping chunk upload scenario. Save and return chunk's SHA-256 result only if there is no more bytes to skip,
        -- because we only know SHA-256 of farthest chunk uploaded and nothing in between.

        self.real_size = ctx.range_from + ctx.content_length
        shactx_to_file(ctx.file_path, self.sha256_ctx, self.real_size)

        local md = ffi.new("char[?]", 32)
        if crypto.SHA256_Final(md, self.sha256_ctx) == 0 then
          return string.format("SHA256 finalization failed")
        end
        local hexresult = util.tohex(ffi.string(md, 32))
        if ctx.sha256 then
          -- already provided by client, let's check it
          if ctx.sha256 ~= hexresult then
            return {400, string.format("Chunk SHA-256 mismatch client=[%s] server=[%s]", ctx.sha256, hexresult)}
          end
        end
        ctx.sha256 = hexresult
      end

      if ctx.sha256 then ngx.header['X-SHA256'] = ctx.sha256 end
    end
  }
end

return {
  handler = handler,
  validhex = validhex
}
