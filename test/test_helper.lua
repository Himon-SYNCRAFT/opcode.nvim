local M = {}

local _captured = {}

function M.capture_notify()
   _captured = {}
   local orig = vim.notify
   vim.notify = function(msg, level, opts)
      table.insert(_captured, { msg = msg, level = level, opts = opts })
      if orig then orig(msg, level, opts) end
   end
   return function()
      vim.notify = orig
      return _captured
   end
end

function M.assert_notify_contains(substring, level)
   for _, n in ipairs(_captured) do
      if type(n.msg) == "string" and n.msg:find(substring, 1, true) and n.level == level then
         return true
      end
   end
   error(
      string.format(
         "Expected notify with '%s' at level %d, got:\n%s",
         substring,
         level,
         vim.inspect(_captured)
      )
   )
end

function M.assert_no_notify(level)
   for _, n in ipairs(_captured) do
      if n.level == level then
         error(string.format("Expected no notify at level %d, got:\n%s", level, vim.inspect(_captured)))
      end
   end
   return true
end

function M.reset_plugin()
   package.loaded["opencode"] = nil
end

function M.valid_config(overrides)
   return vim.tbl_extend("force", {
      port = 4096,
      hostname = "127.0.0.1",
      command = "alacritty -e opencode --port {port}",
   }, overrides or {})
end

local _passed = 0
local _failed = 0
local _errors = {}

function M.run(name, fn)
   local ok, err = pcall(fn)
   if ok then
      _passed = _passed + 1
      print(string.format("  PASS: %s", name))
   else
      _failed = _failed + 1
      table.insert(_errors, { name = name, err = err })
      print(string.format("  FAIL: %s\n    %s", name, tostring(err)))
   end
end

function M.summary()
   print(string.format("\n%d passed, %d failed", _passed, _failed))
   if #_errors > 0 then
      print("\nFailures:")
      for _, e in ipairs(_errors) do
         print(string.format("  %s: %s", e.name, e.err))
      end
   end
   return _failed == 0
end

function M.exit()
   local ok = M.summary()
   vim.cmd("qa!")
   -- nvim -l returns non-zero if we write error, but qa! exits 0
   -- so use os.exit for failure
   if not ok then os.exit(1) end
end

return M
