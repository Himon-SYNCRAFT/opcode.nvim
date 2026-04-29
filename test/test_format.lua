local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")
package.path = root .. "/test/?.lua;" .. root .. "/lua/?.lua;" .. root .. "/lua/?/init.lua;" .. package.path

local h = require("test_helper")
local format = require("opcode.format")

h.run("format_file returns relative path as-is", function()
   local result = format.format_file("src/main.lua")
   assert(result == "src/main.lua", string.format("expected 'src/main.lua', got '%s'", result))
end)

h.run("format_selection produces path#L5-9 header with lua code block", function()
   local result = format.format_selection("src/main.lua", 5, 9, "local x = 1\nreturn x")
   local expected = "src/main.lua#L5-9\n```lua\nlocal x = 1\nreturn x\n```"
   assert(result == expected, string.format("expected:\n%s\n\ngot:\n%s", expected, result))
end)

h.run("format_line produces path#L7 header with code block", function()
   local result = format.format_line("folder/file.py", 7, 'print("hello")')
   local expected = 'folder/file.py#L7\n```python\nprint("hello")\n```'
   assert(result == expected, string.format("expected:\n%s\n\ngot:\n%s", expected, result))
end)

h.run("format_selection uses empty lang for unknown extension", function()
   local result = format.format_selection("config.xyz", 1, 3, "data")
   assert(result:find("```\n", 1, true), string.format("expected empty lang in block, got:\n%s", result))
end)

h.run("format_line uses empty lang for file without extension", function()
   local result = format.format_line("Makefile", 10, "build:")
   assert(result:find("```\n", 1, true), string.format("expected empty lang in block, got:\n%s", result))
end)

h.run("format_selection preserves leading whitespace in content", function()
   local content = "  local x = 1\n    return x"
   local result = format.format_selection("src/main.lua", 10, 11, content)
   assert(result:find("  local x = 1", 1, true), string.format("expected leading whitespace preserved, got:\n%s", result))
   assert(result:find("    return x", 1, true), string.format("expected indentation preserved, got:\n%s", result))
end)

h.exit()
