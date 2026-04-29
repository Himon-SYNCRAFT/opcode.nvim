local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")
package.path = root .. "/test/?.lua;" .. root .. "/lua/?.lua;" .. root .. "/lua/?/init.lua;" .. package.path

local h = require("test_helper")

local function mock_api_list_sessions(response)
   local api = require("opcode.api")
   local orig = api.list_sessions
   api.list_sessions = function(hostname, port, cb)
      cb(response.err, response.data)
   end
   return function()
      api.list_sessions = orig
   end
end

local function mock_ui_select(items, opts, on_choice)
   local captured = { items = items, opts = opts }
   return captured, on_choice
end

h.run("list_sessions calls api with hostname and port from config", function()
   h.reset_plugin()
   package.loaded["opcode.commands"] = nil
   package.loaded["opcode.state"] = nil
   package.loaded["opcode.api"] = nil

   local api = require("opcode.api")
   local captured_host, captured_port
   local orig_list = api.list_sessions
   api.list_sessions = function(host, port, cb)
      captured_host = host
      captured_port = port
      cb(nil, {})
   end

   local orig_select = vim.ui.select
   vim.ui.select = function() end

   local commands = require("opcode.commands")
   commands.list_sessions({ hostname = "192.168.1.1", port = 8080 })

   api.list_sessions = orig_list
   vim.ui.select = orig_select

   assert(captured_host == "192.168.1.1", string.format("expected host '192.168.1.1', got '%s'", captured_host))
   assert(captured_port == 8080, string.format("expected port 8080, got %s", tostring(captured_port)))
end)

h.run("list_sessions formats sessions and includes create option in picker", function()
   h.reset_plugin()
   package.loaded["opcode.commands"] = nil
   package.loaded["opcode.state"] = nil
   package.loaded["opcode.api"] = nil

   local api = require("opcode.api")
   local orig_list = api.list_sessions
   api.list_sessions = function(_, _, cb)
      cb(nil, {
         { id = "abc123", title = "My Session", createdAt = "2026-04-29T14:32:00Z" },
         { id = "def456", title = "Another", createdAt = "2026-04-29T09:15:00Z" },
      })
   end

   local captured_items
   local orig_select = vim.ui.select
   vim.ui.select = function(items, opts, on_choice)
      captured_items = items
   end

   local commands = require("opcode.commands")
   commands.list_sessions({ hostname = "127.0.0.1", port = 4096 })

   api.list_sessions = orig_list
   vim.ui.select = orig_select

   assert(captured_items ~= nil, "expected vim.ui.select to be called")
   assert(#captured_items == 3, string.format("expected 3 items (2 sessions + create), got %d", #captured_items))
   assert(
      captured_items[1] == "[2026-04-29 14:32] My Session (abc123)",
      string.format("unexpected format: %s", captured_items[1])
   )
   assert(
      captured_items[2] == "[2026-04-29 09:15] Another (def456)",
      string.format("unexpected format: %s", captured_items[2])
   )
   assert(
      captured_items[3] == "[+] Create new session",
      string.format("expected create option last, got: %s", captured_items[3])
   )
end)

h.run("selecting a session stores its id in state", function()
   h.reset_plugin()
   package.loaded["opcode.commands"] = nil
   package.loaded["opcode.state"] = nil
   package.loaded["opcode.api"] = nil

   local api = require("opcode.api")
   local orig_list = api.list_sessions
   api.list_sessions = function(_, _, cb)
      cb(nil, {
         { id = "sess-xyz", title = "Picked", createdAt = "2026-04-29T10:00:00Z" },
      })
   end

   local orig_select = vim.ui.select
   vim.ui.select = function(items, opts, on_choice)
      on_choice(items[1], 1)
   end

   local commands = require("opcode.commands")
   local sstate = require("opcode.state")
   commands.list_sessions({ hostname = "127.0.0.1", port = 4096 })

   api.list_sessions = orig_list
   vim.ui.select = orig_select

   assert(
      sstate.get_selected_session() == "sess-xyz",
      string.format("expected 'sess-xyz', got %s", vim.inspect(sstate.get_selected_session()))
   )
end)

h.run("selecting create new stores sentinel value in state", function()
   h.reset_plugin()
   package.loaded["opcode.commands"] = nil
   package.loaded["opcode.state"] = nil
   package.loaded["opcode.api"] = nil

   local api = require("opcode.api")
   local orig_list = api.list_sessions
   api.list_sessions = function(_, _, cb)
      cb(nil, {})
   end

   local orig_select = vim.ui.select
   vim.ui.select = function(items, opts, on_choice)
      on_choice(items[#items], #items)
   end

   local commands = require("opcode.commands")
   local sstate = require("opcode.state")
   commands.list_sessions({ hostname = "127.0.0.1", port = 4096 })

   api.list_sessions = orig_list
   vim.ui.select = orig_select

   assert(
      sstate.get_selected_session() == "__create_new__",
      string.format("expected sentinel, got %s", vim.inspect(sstate.get_selected_session()))
   )
end)

h.run("list_sessions notifies error when api call fails", function()
   h.reset_plugin()
   package.loaded["opcode.commands"] = nil
   package.loaded["opcode.state"] = nil
   package.loaded["opcode.api"] = nil

   local api = require("opcode.api")
   local orig_list = api.list_sessions
   api.list_sessions = function(_, _, cb)
      cb({ message = "Network error", code = 7 }, nil)
   end

   local select_called = false
   local orig_select = vim.ui.select
   vim.ui.select = function()
      select_called = true
   end

   local done = h.capture_notify()
   local commands = require("opcode.commands")
   commands.list_sessions({ hostname = "127.0.0.1", port = 4096 })

   api.list_sessions = orig_list
   vim.ui.select = orig_select
   done()

   h.assert_notify_contains("failed to fetch sessions", vim.log.levels.ERROR)
   assert(not select_called, "vim.ui.select should not be called on error")
end)

h.run("setup registers OpenCodeListSessions command", function()
   h.reset_plugin()
   package.loaded["opcode.commands"] = nil
   package.loaded["opcode.state"] = nil
   package.loaded["opcode.api"] = nil

   require("opcode").setup(h.valid_config())

   local cmds = vim.api.nvim_get_commands({})
   assert(
      cmds["OpenCodeListSessions"] ~= nil,
      "expected OpenCodeListSessions command to be registered"
   )
end)

h.exit()
