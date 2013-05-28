local string = string
local io = io

module(...)

-- Convert any binary string to hex
function tohex(str)
    return (str:gsub('.', function (c)
        return string.format('%02x', string.byte(c))
    end))
end

-- This is random string generator generating SHA1 compatible strings
function random_sha1()
    local ur = io.open("/dev/urandom", "r")
    local random_bin = ur:read(20)  -- loads 160 bits
    ur:close()
    return tohex(random_bin)  -- returns 40 hexadecimal characters
end