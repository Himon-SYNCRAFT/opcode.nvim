local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")
package.path = root .. "/test/?.lua;" .. root .. "/lua/?.lua;" .. root .. "/lua/?/init.lua;" .. package.path

local h = require("test_helper")
local project = require("opcode.project")

h.run("get_root returns CWD when no API config and no .git found", function()
   local cwd = "/tmp/some/project"
   local orig_getcwd = vim.fn.getcwd
   vim.fn.getcwd = function()
      return cwd
   end

   local orig_expand = vim.fn.expand
   vim.fn.expand = function()
      return "/tmp/some/project"
   end

   local result = project.get_root({})
   vim.fn.getcwd = orig_getcwd
   vim.fn.expand = orig_expand

   assert(result == cwd, string.format("expected %s, got %s", cwd, result))
end)

h.run("get_root walks up from buffer dir to find .git", function()
   local tmpdir = vim.fn.tempname()
   os.execute("rm -rf " .. vim.fn.shellescape(tmpdir))
   os.execute("mkdir -p " .. vim.fn.shellescape(tmpdir .. "/deep/sub/dir"))
   os.execute("mkdir " .. vim.fn.shellescape(tmpdir .. "/.git"))

   local orig_expand = vim.fn.expand
   vim.fn.expand = function(spec)
      if spec == "%:p:h" then
         return tmpdir .. "/deep/sub/dir"
      end
      return orig_expand(spec)
   end

   local result = project.get_root({})
   vim.fn.expand = orig_expand
   os.execute("rm -rf " .. vim.fn.shellescape(tmpdir))

   assert(result == tmpdir, string.format("expected %s, got %s", tmpdir, result))
end)

h.run("get_root queries API first and returns root from response", function()
   local api_root = "/home/user/api-project"
   local orig_system = vim.system
   vim.system = function(cmd)
      return {
         wait = function()
            return {
               code = 0,
               stdout = vim.json.encode({ root = api_root }),
            }
         end,
      }
   end

   local result = project.get_root({ hostname = "127.0.0.1", port = 4096 })
   vim.system = orig_system

   assert(result == api_root, string.format("expected %s, got %s", api_root, result))
end)

h.run("get_root prefers API over .git when both available", function()
   local api_root = "/home/user/api-project"
   local orig_system = vim.system
   vim.system = function(cmd)
      return {
         wait = function()
            return {
               code = 0,
               stdout = vim.json.encode({ root = api_root }),
            }
         end,
      }
   end

   local tmpdir = vim.fn.tempname()
   os.execute("rm -rf " .. vim.fn.shellescape(tmpdir))
   os.execute("mkdir -p " .. vim.fn.shellescape(tmpdir .. "/sub"))
   os.execute("mkdir " .. vim.fn.shellescape(tmpdir .. "/.git"))

   local orig_expand = vim.fn.expand
   vim.fn.expand = function(spec)
      if spec == "%:p:h" then return tmpdir .. "/sub" end
      return orig_expand(spec)
   end

   local result = project.get_root({ hostname = "127.0.0.1", port = 4096 })
   vim.system = orig_system
   vim.fn.expand = orig_expand
   os.execute("rm -rf " .. vim.fn.shellescape(tmpdir))

   assert(result == api_root, string.format("expected API root %s, got %s", api_root, result))
end)

h.run("get_root falls through to .git when API fails, emits WARN", function()
   local orig_system = vim.system
   vim.system = function(cmd)
      return {
         wait = function()
            return { code = 7, stdout = "" }
         end,
      }
   end

   local tmpdir = vim.fn.tempname()
   os.execute("rm -rf " .. vim.fn.shellescape(tmpdir))
   os.execute("mkdir -p " .. vim.fn.shellescape(tmpdir .. "/sub"))
   os.execute("mkdir " .. vim.fn.shellescape(tmpdir .. "/.git"))

   local orig_expand = vim.fn.expand
   vim.fn.expand = function(spec)
      if spec == "%:p:h" then return tmpdir .. "/sub" end
      return orig_expand(spec)
   end

   local done = h.capture_notify()
   local result = project.get_root({ hostname = "127.0.0.1", port = 4096 })
   local notified = done()

   vim.system = orig_system
   vim.fn.expand = orig_expand
   os.execute("rm -rf " .. vim.fn.shellescape(tmpdir))

   assert(result == tmpdir, string.format("expected git root %s, got %s", tmpdir, result))
   h.assert_notify_contains("project", vim.log.levels.WARN)
end)

h.exit()
