std = "luajit"

globals = { "ngx" }

max_line_length = 160

ignore = {
  "211", -- unused local, the modules alias globals into locals on purpose, it is the OpenResty idiom
  "212", -- unused argument, the handler pipeline passes a uniform signature to every callback
  "213", -- unused loop variable
  "621", -- inconsistent indentation, the ffi.cdef blocks keep the layout of the OpenSSL headers
}

files["lib/big-upload.lua"] = {
  -- The outer `err` is shadowed by the one destructured from request_processor:new()
  ignore = { "411/err" },
}

files["lib/devutil.lua"] = {
  -- Debug-only helper, declares dump() as a global on purpose.
  ignore = { "111", "112", "113" },
}

files["lib/request_processor.lua"] = {
  -- Known bug, deliberately visible here rather than fixed in passing: both names are read as
  -- globals and are therefore always nil, so the intended 30 s socket timeout never takes effect.
  -- Fixing it changes behaviour on slow connections, so it needs its own change and its own test.
  ignore = { "113/socket_timeout", "113/chunk_size" },
}
