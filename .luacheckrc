std = "luajit"

globals = { "ngx" }

max_line_length = 160

ignore = {
  "212", -- unused argument, the handler pipeline passes a uniform signature to every callback
  "213", -- unused loop variable
}
