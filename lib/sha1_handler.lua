-- Copyright (C) 2013 Piotr Gaertig
-- SHA1 shortcut function handler for nginx-big-upload pipeline
-- This is stateless handler, it saves .sha1 file with SHA1 context data.

local ffi = require('ffi')
local tonumber = tonumber
local string = string
local ngx = ngx
local table = table
local io = io
local assert = assert
local concat = table.concat
local util = require('util')

module(...)

function validhex(sha1hex) return #sha1hex <= 40 and string.match(sha1hex, "^%x+$") end

local crypto = ffi.load('crypto')

-- extracted from https://github.com/openssl/openssl/blob/master/crypto/sha/sha.h
ffi.cdef[[

  typedef struct SHAstate_st
  {
    	unsigned int h0,h1,h2,h3,h4;
	    unsigned int Nl,Nh;
	    unsigned int data[16];
	    unsigned int num;
  } SHA_CTX; //96 bytes

  int SHA1_Init(SHA_CTX *shactx);
  int SHA1_Update(SHA_CTX *shactx, const void *data, unsigned long len);
  int SHA1_Final(unsigned char *md, SHA_CTX *shactx);
]]

local function shactx_from_file(path)

end

local function shactx_to_file(file_path, shactx, offset)
  local out = assert(io.open(file_path..'.shactx', "wb"))
  local binctx = ffi.string(shactx, 96)
  out:write(offset)
  out:write("\n")
  out:write(binctx)
  assert(out:close())
end

local function shactx_from_file(file_path)
  local inp = io.open(file_path..'.shactx', "rb")
  if inp then
    file_size = tonumber(inp:read("*line"))
    file_data = inp:read("*all")
    assert(inp:close())
    -- ffi.copy(file_data, shactx, 96)
    return file_size, ffi.cast("SHA_CTX*", file_data)
  end
  return
end


function handler(storage_path)
  return {

    on_body_start = function (self, ctx)
      self.sha1_ctx = ffi.new("SHA_CTX")
      self.skip_bytes = 0
      if not ctx.first_chunk then
        local file_path = concat({storage_path, ctx.id}, "/")  -- file based backends not initialized yet
        self.real_size, self.sha1_ctx = shactx_from_file(file_path)

        --overlapping chunk upload, need to skip repeated data
        self.skip_bytes = self.real_size - ctx.range_from
        return
      end
      if crypto.SHA1_Init(self.sha1_ctx) == 0 then
        return string.format("SHA1 initialization failed")
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
        if crypto.SHA1_Update(self.sha1_ctx, body, #body) == 0 then
          return string.format("SHA1 update failed")
        end
      end
    end,

    on_body_end = function (self, ctx)
      if self.skip_bytes == 0 then
        -- In overlapping chunk upload scenario. Save and return chunk's SHA-1 result only if there is no more bytes to skip,
        -- because we only know SHA-1 of farthest chunk uploaded and nothing in between.

        self.real_size = ctx.range_from + ctx.content_length
        shactx_to_file(ctx.file_path, self.sha1_ctx, self.real_size)

        local md = ffi.new("char[?]", 20)
        if crypto.SHA1_Final(md, self.sha1_ctx) == 0 then
          return string.format("SHA1 finalization failed")
        end
        local hexresult = util.tohex(ffi.string(md, 20))
        if ctx.sha1 then
          -- already provided by client, let's check it
          if ctx.sha1 ~= hexresult then
            return {400, string.format("Chunk SHA-1 mismatch client=[%s] server=[%s]", ctx.sha1, hexresult)}
          end
        end
        ctx.sha1 = hexresult
      end

      if ctx.sha1 then ngx.header['X-SHA1'] = ctx.sha1 end
    end
  }
end
