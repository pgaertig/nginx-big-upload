-- this file analyzes the first chunk for recognizable mime types
-- it depends on ctx.authorized_mime_type value added during authentication

local ngx = ngx
local string = string


module(...)



function find_mime_type (bytes)
  local b = ""
  for i=1, 8 do
    b = b .. string.upper(string.format("%x", string.byte(bytes, i)))
    if b     == "FFD8FFDB" then return "jpg"
    elseif b == "FFD8FFE0" then return "jpg"
    elseif b == "49460001" then return "jpg"
    elseif b == "FFD8FFE1" then return "jpg"
    elseif b == "69660000" then return "jpg"
    elseif b == "49492A00" then return "tif"
    elseif b == "4D4D002A" then return "tif"
    end
    if b     == "474946383761" then return "gif"
    elseif b == "474946383961" then return "gif"
    elseif b == "89504E470D0A" then return "gif"
    end
    if b == "89504E470D0A1A0A" then return "png"
    end
  end
  return nil
end


function handler()
  return {

    on_body_start = function (self, ctx)
    end,

    on_body = function (self, ctx, body)
      if ctx.first_chunk then
        if ngx.ctx.authorized_mime_type == nil then
          self.on_body_end = nil
          ngx.log(ngx.ERR, "Authorized mime type is not defined")
          return {400, "Authorized mime type is not defined"}
        end
        if ctx.detected_mime_type ~= nil then  -- already detected...
          return
        end
        ctx.detected_mime_type = find_mime_type(body)
        if ngx.ctx.authorized_mime_type ~= ctx.detected_mime_type then
          self.on_body_end = nil
          if ctx.detected_mime_type == nil then
            ctx.detected_mime_type = ""
          end
          ngx.log(ngx.ERR, string.format("Authorized mime type mismatch. Authorized: [%s]. Detected: [%s]", ngx.ctx.authorized_mime_type, ctx.detected_mime_type))
          return {400, string.format("Authorized mime type mismatch. Authorized: [%s]. Detected: [%s]", ngx.ctx.authorized_mime_type, ctx.detected_mime_type)}
        end
      end
    end,

    on_body_end = function (self, ctx)
    end

  }
end
