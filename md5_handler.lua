-- Copyright (C) 2013 Piotr Gaertig
-- SHA1 shortcut function handler for nginx-big-upload pipeline
-- This is stateless handler, it saves .sha1 file with SHA1 context data.
--  yarshure hack sha1 to md5
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

function validmd5hex(md5hex) return #md5hex <= 32 and string.match(md5hex, "^%x+$") end

local crypto = ffi.load('crypto')

-- extracted from https://github.com/openssl/openssl/blob/master/crypto/sha/sha.h
ffi.cdef[[

  typedef struct MD5state_st
  {
  unsigned int A,B,C,D;
  unsigned int Nl,Nh;
  unsigned int data[16];
  unsigned int num;
  } MD5_CTX;

  int MD5_Init(MD5_CTX *c);
  int MD5_Update(MD5_CTX *c, const void *data, size_t len);
  int MD5_Final(unsigned char *md, MD5_CTX *c);

]]

local function md5ctx_from_file(path)

end

local function md5ctx_to_file(file_path, md5ctx, offset)
  local out = assert(io.open(file_path..'.md5ctx', "wb"))
  local binctx = ffi.string(md5ctx, 92) -- 96?
  out:write(offset)
  out:write("\n")
  out:write(binctx)
  assert(out:close())
end

local function md5ctx_from_file(file_path)
  local inp = io.open(file_path..'.md5ctx', "rb")
  if inp then
    file_size = tonumber(inp:read("*line"))
    file_data = inp:read("*all")
    assert(inp:close())
    -- ffi.copy(file_data, shactx, 96)
    return file_size, ffi.cast("MD5_CTX*", file_data)
  end
  return
end


function handler(storage_path)
  return {

    on_body_start = function (self, ctx)
      self.md5_ctx = ffi.new("MD5_CTX")
      self.skip_bytes = 0
      if not ctx.first_chunk then
        local file_path = concat({storage_path, ctx.id}, "/")  -- file based backends not initialized yet
        self.real_size, self.sha1_ctx = md5ctx_from_file(file_path)

        --overlapping chunk upload, need to skip repeated data
        self.skip_bytes = self.real_size - ctx.range_from
        return
      end
      if crypto.MD5_Init(self.md5_ctx) == 0 then
        return string.format("md5 initialization failed")
      end
      ngx.log(ngx.DEBUG, "on_body_start")
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
      ngx.log(ngx.DEBUG, "on_body")
      if body and #body > 0 then
        if crypto.MD5_Update(self.md5_ctx, body, #body) == 0 then
          return string.format("MD5 update failed")
        end
      end
    end,

    on_body_end = function (self, ctx)
      if self.skip_bytes == 0 then
        -- In overlapping chunk upload scenario. Save and return chunk's SHA-1 result only if there is no more bytes to skip,
        -- because we only know SHA-1 of farthest chunk uploaded and nothing in between.
        
        self.real_size = ctx.range_from + ctx.content_length
        
        md5ctx_to_file(ctx.file_path, self.md5_ctx, self.real_size)
        ngx.log(ngx.DEBUG, "on_body_end"..self.real_size)
        
        local md = ffi.new("char[?]", 16) --?
        if crypto.MD5_Final(md, self.md5_ctx) == 0 then
          return string.format("MD5 finalization failed")
        end
        ngx.log(ngx.DEBUG, "on_body_end")
        local hexresult = util.tohex(ffi.string(md, 16))
        if ctx.md5 then
          -- already provided by client, let's check it
          if ctx.md5 ~= hexresult then
            return {400, string.format("Chunk MD5 mismatch client=[%s] server=[%s]", ctx.md5, hexresult)}
          end
        end
        ngx.log(ngx.DEBUG, "on_body_end")
        ctx.md5 = hexresult
      end

      if ctx.md5 then ngx.header['X-MD5'] = ctx.md5 end
    end
  }
end
