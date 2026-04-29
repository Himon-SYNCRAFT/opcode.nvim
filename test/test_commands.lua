local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")
package.path = root .. "/test/?.lua;" .. root .. "/lua/?.lua;" .. root .. "/lua/?/init.lua;" .. package.path

local h = require("test_helper")

local function mock_system_capture(response)
   local orig = vim.system
   local captured_cmd
   vim.system = function(cmd, opts, on_exit)
      captured_cmd = cmd
      on_exit(response)
   end
   return function()
      vim.system = orig
      return captured_cmd
   end
end

h.run("connect launches terminal command with port substituted", function()
   h.reset_plugin()
   package.loaded["opcode.commands"] = nil

   local stop_capture = mock_system_capture({ code = 0, stderr = "" })
   require("opcode").setup({
      port = 4096,
      hostname = "127.0.0.1",
      command = "alacritty -e opencode --port {port}",
   })
   require("opcode").connect()
   local cmd = stop_capture()

   assert(cmd ~= nil, "expected vim.system to be called")
   assert(
      cmd == "alacritty -e opencode --port 4096",
      string.format("expected 'alacritty -e opencode --port 4096', got '%s'", vim.inspect(cmd))
   )
end)

h.run("connect notifies on command error", function()
   h.reset_plugin()
   package.loaded["opcode.commands"] = nil

   local stop_capture = mock_system_capture({ code = 1, stderr = "command not found" })
   local done = h.capture_notify()
   require("opcode").setup({
      port = 4096,
      hostname = "127.0.0.1",
      command = "alacritty -e opencode --port {port}",
   })
   require("opcode").connect()
   stop_capture()
   done()

   h.assert_notify_contains("terminal", vim.log.levels.ERROR)
end)

h.run("setup registers OpenCodeConnect command", function()
   h.reset_plugin()
   package.loaded["opcode.commands"] = nil

   require("opcode").setup({
      port = 4096,
      hostname = "127.0.0.1",
      command = "alacritty -e opencode --port {port}",
   })

   local cmds = vim.api.nvim_get_commands({})
   assert(
      cmds["OpenCodeConnect"] ~= nil,
      "expected OpenCodeConnect command to be registered"
   )
end)

h.run("create_session calls api and updates selected_session_id on success", function()
   h.reset_plugin()
   package.loaded["opcode.commands"] = nil
   package.loaded["opcode.state"] = nil
   package.loaded["opcode.api"] = nil

   local api = require("opcode.api")
   local orig_create = api.create_session
   api.create_session = function(hostname, port, title, cb)
      cb(nil, { id = "sess-new123", title = title })
   end

   local done = h.capture_notify()
   local commands = require("opcode.commands")
   local sstate = require("opcode.state")
   commands.create_session({ hostname = "127.0.0.1", port = 4096 }, "My Session")

   api.create_session = orig_create
   done()

   assert(
      sstate.get_selected_session() == "sess-new123",
      string.format("expected 'sess-new123', got %s", vim.inspect(sstate.get_selected_session()))
   )
   h.assert_notify_contains("My Session", vim.log.levels.INFO)
end)

h.run("create_session uses CWD name as title when none provided", function()
   h.reset_plugin()
   package.loaded["opcode.commands"] = nil
   package.loaded["opcode.state"] = nil
   package.loaded["opcode.api"] = nil

   local api = require("opcode.api")
   local captured_title
   local orig_create = api.create_session
   api.create_session = function(hostname, port, title, cb)
      captured_title = title
      cb(nil, { id = "sess-auto", title = title })
   end

   local done = h.capture_notify()
   local commands = require("opcode.commands")
   commands.create_session({ hostname = "127.0.0.1", port = 4096 })

   api.create_session = orig_create
   done()

   assert(
      type(captured_title) == "string" and #captured_title > 0,
      string.format("expected non-empty title, got %s", vim.inspect(captured_title))
    )
end)

h.run("create_session notifies error and does not update state on API failure", function()
   h.reset_plugin()
   package.loaded["opcode.commands"] = nil
   package.loaded["opcode.state"] = nil
   package.loaded["opcode.api"] = nil

   local api = require("opcode.api")
   local orig_create = api.create_session
   api.create_session = function(hostname, port, title, cb)
      cb({ message = "Network error", code = 7 }, nil)
   end

   local done = h.capture_notify()
   local commands = require("opcode.commands")
   local sstate = require("opcode.state")
   commands.create_session({ hostname = "127.0.0.1", port = 4096 }, "Fail Session")

   api.create_session = orig_create
   done()

   assert(
      sstate.get_selected_session() == nil,
      string.format("expected nil state, got %s", vim.inspect(sstate.get_selected_session()))
   )
   h.assert_notify_contains("failed to create session", vim.log.levels.ERROR)
end)

h.run("setup registers OpenCodeCreateSession command", function()
   h.reset_plugin()
   package.loaded["opcode.commands"] = nil

   require("opcode").setup(h.valid_config())

   local cmds = vim.api.nvim_get_commands({})
   assert(
      cmds["OpenCodeCreateSession"] ~= nil,
      "expected OpenCodeCreateSession command to be registered"
   )
end)

h.run("send_file errors when no session selected", function()
   h.reset_plugin()
   package.loaded["opcode.commands"] = nil
   package.loaded["opcode.state"] = nil
   package.loaded["opcode.api"] = nil
   package.loaded["opcode.project"] = nil

   local sstate = require("opcode.state")
   sstate.clear_selected_session()

   local done = h.capture_notify()
   local commands = require("opcode.commands")
   commands.send_file(h.valid_config())

   done()
   h.assert_notify_contains("no session", vim.log.levels.ERROR)
end)

h.run("send_file sends relative path via append_prompt on success", function()
   h.reset_plugin()
   package.loaded["opcode.commands"] = nil
   package.loaded["opcode.state"] = nil
   package.loaded["opcode.api"] = nil
   package.loaded["opcode.project"] = nil
   package.loaded["opcode.format"] = nil

   local sstate = require("opcode.state")
   sstate.set_selected_session("sess-xyz")

   local api = require("opcode.api")
   local orig_append = api.append_prompt
   local captured_args = {}
   api.append_prompt = function(hostname, port, session_id, text, cb)
      captured_args = { hostname = hostname, port = port, session_id = session_id, text = text }
      cb(nil, {})
   end

   local project = require("opcode.project")
   local orig_get_root = project.get_root
   project.get_root = function()
      return "/home/user/project"
   end

   local orig_expand = vim.fn.expand
   vim.fn.expand = function(expr)
      if expr == "%:p" then return "/home/user/project/src/main.lua" end
      return orig_expand(expr)
   end

   local commands = require("opcode.commands")
   commands.send_file(h.valid_config())

   api.append_prompt = orig_append
   project.get_root = orig_get_root
   vim.fn.expand = orig_expand

   assert(captured_args.hostname == "127.0.0.1", "expected hostname 127.0.0.1")
   assert(captured_args.port == 4096, "expected port 4096")
   assert(captured_args.session_id == "sess-xyz", "expected session_id sess-xyz")
   assert(captured_args.text == "src/main.lua",
      string.format("expected relative path 'src/main.lua', got '%s'", captured_args.text))
end)

h.run("send_file notifies error on API failure", function()
   h.reset_plugin()
   package.loaded["opcode.commands"] = nil
   package.loaded["opcode.state"] = nil
   package.loaded["opcode.api"] = nil
   package.loaded["opcode.project"] = nil
   package.loaded["opcode.format"] = nil

   local sstate = require("opcode.state")
   sstate.set_selected_session("sess-xyz")

   local api = require("opcode.api")
   local orig_append = api.append_prompt
   api.append_prompt = function(hostname, port, session_id, text, cb)
      cb({ message = "connection refused" }, nil)
   end

   local proj = require("opcode.project")
   local orig_get_root = proj.get_root
   proj.get_root = function() return "/home/user/project" end

   local orig_expand = vim.fn.expand
   vim.fn.expand = function(expr)
      if expr == "%:p" then return "/home/user/project/foo.lua" end
      return orig_expand(expr)
   end

   local done = h.capture_notify()
   local commands = require("opcode.commands")
   commands.send_file(h.valid_config())

   api.append_prompt = orig_append
   proj.get_root = orig_get_root
   vim.fn.expand = orig_expand
   done()

   h.assert_notify_contains("failed to send file", vim.log.levels.ERROR)
end)

h.run("send_file shows INFO notification with path on success", function()
   h.reset_plugin()
   package.loaded["opcode.commands"] = nil
   package.loaded["opcode.state"] = nil
   package.loaded["opcode.api"] = nil
   package.loaded["opcode.project"] = nil
   package.loaded["opcode.format"] = nil

   local sstate = require("opcode.state")
   sstate.set_selected_session("sess-abc")

   local api = require("opcode.api")
   local orig_append = api.append_prompt
   api.append_prompt = function(_, _, _, _, cb) cb(nil, {}) end

   local proj = require("opcode.project")
   local orig_get_root = proj.get_root
   proj.get_root = function() return "/proj" end

   local orig_expand = vim.fn.expand
   vim.fn.expand = function(expr)
      if expr == "%:p" then return "/proj/lib/util.lua" end
      return orig_expand(expr)
   end

   local done = h.capture_notify()
   local commands = require("opcode.commands")
   commands.send_file(h.valid_config())

   api.append_prompt = orig_append
   proj.get_root = orig_get_root
   vim.fn.expand = orig_expand
   done()

   h.assert_notify_contains("lib/util.lua", vim.log.levels.INFO)
end)

h.run("send_file skips INFO notification when notify disabled", function()
   h.reset_plugin()
   package.loaded["opcode.commands"] = nil
   package.loaded["opcode.state"] = nil
   package.loaded["opcode.api"] = nil
   package.loaded["opcode.project"] = nil
   package.loaded["opcode.format"] = nil

   local sstate = require("opcode.state")
   sstate.set_selected_session("sess-abc")

   local api = require("opcode.api")
   local orig_append = api.append_prompt
   api.append_prompt = function(_, _, _, _, cb) cb(nil, {}) end

   local proj = require("opcode.project")
   local orig_get_root = proj.get_root
   proj.get_root = function() return "/proj" end

   local orig_expand = vim.fn.expand
   vim.fn.expand = function(expr)
      if expr == "%:p" then return "/proj/foo.lua" end
      return orig_expand(expr)
   end

   local done = h.capture_notify()
   local commands = require("opcode.commands")
   commands.send_file(h.valid_config({ notify = false }))

   api.append_prompt = orig_append
   proj.get_root = orig_get_root
   vim.fn.expand = orig_expand
   done()

   h.assert_no_notify(vim.log.levels.INFO)
end)

h.run("setup registers OpenCodeSendFile command", function()
    h.reset_plugin()
    package.loaded["opcode.commands"] = nil

    require("opcode").setup(h.valid_config())

    local cmds = vim.api.nvim_get_commands({})
    assert(
       cmds["OpenCodeSendFile"] ~= nil,
       "expected OpenCodeSendFile command to be registered"
    )
end)

h.run("send_selection errors when no session selected", function()
    h.reset_plugin()
    package.loaded["opcode.commands"] = nil
    package.loaded["opcode.state"] = nil
    package.loaded["opcode.api"] = nil
    package.loaded["opcode.project"] = nil
    package.loaded["opcode.format"] = nil

    local sstate = require("opcode.state")
    sstate.clear_selected_session()

    local done = h.capture_notify()
    local commands = require("opcode.commands")
    commands.send_selection(h.valid_config())

    done()
    h.assert_notify_contains("no session", vim.log.levels.ERROR)
end)

h.run("send_selection errors when no visual selection", function()
    h.reset_plugin()
    package.loaded["opcode.commands"] = nil
    package.loaded["opcode.state"] = nil
    package.loaded["opcode.api"] = nil
    package.loaded["opcode.project"] = nil
    package.loaded["opcode.format"] = nil

    local sstate = require("opcode.state")
    sstate.set_selected_session("sess-abc")

    local orig_getregion = vim.fn.getregion
    vim.fn.getregion = function()
        return {}
    end

    local done = h.capture_notify()
    local commands = require("opcode.commands")
    commands.send_selection(h.valid_config())

    vim.fn.getregion = orig_getregion
    done()
    h.assert_notify_contains("no selection", vim.log.levels.ERROR)
end)

h.run("send_selection sends formatted selection via append_prompt", function()
    h.reset_plugin()
    package.loaded["opcode.commands"] = nil
    package.loaded["opcode.state"] = nil
    package.loaded["opcode.api"] = nil
    package.loaded["opcode.project"] = nil
    package.loaded["opcode.format"] = nil

    local sstate = require("opcode.state")
    sstate.set_selected_session("sess-sel")

    local api = require("opcode.api")
    local orig_append = api.append_prompt
    local captured_args = {}
    api.append_prompt = function(hostname, port, session_id, text, cb)
        captured_args = { hostname = hostname, port = port, session_id = session_id, text = text }
        cb(nil, {})
    end

    local proj = require("opcode.project")
    local orig_get_root = proj.get_root
    proj.get_root = function() return "/home/user/project" end

    local orig_expand = vim.fn.expand
    vim.fn.expand = function(expr)
        if expr == "%:p" then return "/home/user/project/src/app.lua" end
        return orig_expand(expr)
    end

    local orig_getregion = vim.fn.getregion
    vim.fn.getregion = function()
        return { "local x = 1", "print(x)" }
    end

    local orig_getpos = vim.fn.getpos
    vim.fn.getpos = function(mark)
        if mark == "'<" then return { 0, 5, 1, 0 } end
        if mark == "'>" then return { 0, 6, 9, 0 } end
        return orig_getpos(mark)
    end

    local commands = require("opcode.commands")
    commands.send_selection(h.valid_config())

    api.append_prompt = orig_append
    proj.get_root = orig_get_root
    vim.fn.expand = orig_expand
    vim.fn.getregion = orig_getregion
    vim.fn.getpos = orig_getpos

    assert(captured_args.hostname == "127.0.0.1", "expected hostname 127.0.0.1")
    assert(captured_args.port == 4096, "expected port 4096")
    assert(captured_args.session_id == "sess-sel", "expected session_id sess-sel")
    assert(
        captured_args.text:find("src/app.lua#L5-6", 1, true),
        string.format("expected header 'src/app.lua#L5-6', got:\n%s", captured_args.text)
    )
    assert(
        captured_args.text:find("local x = 1", 1, true),
        string.format("expected content 'local x = 1', got:\n%s", captured_args.text)
    )
end)

h.run("send_selection notifies error on API failure", function()
    h.reset_plugin()
    package.loaded["opcode.commands"] = nil
    package.loaded["opcode.state"] = nil
    package.loaded["opcode.api"] = nil
    package.loaded["opcode.project"] = nil
    package.loaded["opcode.format"] = nil

    local sstate = require("opcode.state")
    sstate.set_selected_session("sess-sel")

    local api = require("opcode.api")
    local orig_append = api.append_prompt
    api.append_prompt = function(_, _, _, _, cb)
        cb({ message = "connection refused" }, nil)
    end

    local proj = require("opcode.project")
    local orig_get_root = proj.get_root
    proj.get_root = function() return "/home/user/project" end

    local orig_expand = vim.fn.expand
    vim.fn.expand = function(expr)
        if expr == "%:p" then return "/home/user/project/foo.lua" end
        return orig_expand(expr)
    end

    local orig_getregion = vim.fn.getregion
    vim.fn.getregion = function() return { "hello" } end

    local orig_getpos = vim.fn.getpos
    vim.fn.getpos = function(mark)
        if mark == "'<" then return { 0, 1, 1, 0 } end
        if mark == "'>" then return { 0, 1, 5, 0 } end
        return orig_getpos(mark)
    end

    local done = h.capture_notify()
    local commands = require("opcode.commands")
    commands.send_selection(h.valid_config())

    api.append_prompt = orig_append
    proj.get_root = orig_get_root
    vim.fn.expand = orig_expand
    vim.fn.getregion = orig_getregion
    vim.fn.getpos = orig_getpos
    done()

    h.assert_notify_contains("failed to send selection", vim.log.levels.ERROR)
end)

h.run("send_selection shows INFO notification with path and line range on success", function()
    h.reset_plugin()
    package.loaded["opcode.commands"] = nil
    package.loaded["opcode.state"] = nil
    package.loaded["opcode.api"] = nil
    package.loaded["opcode.project"] = nil
    package.loaded["opcode.format"] = nil

    local sstate = require("opcode.state")
    sstate.set_selected_session("sess-abc")

    local api = require("opcode.api")
    local orig_append = api.append_prompt
    api.append_prompt = function(_, _, _, _, cb) cb(nil, {}) end

    local proj = require("opcode.project")
    local orig_get_root = proj.get_root
    proj.get_root = function() return "/proj" end

    local orig_expand = vim.fn.expand
    vim.fn.expand = function(expr)
        if expr == "%:p" then return "/proj/lib/util.lua" end
        return orig_expand(expr)
    end

    local orig_getregion = vim.fn.getregion
    vim.fn.getregion = function() return { "return true" } end

    local orig_getpos = vim.fn.getpos
    vim.fn.getpos = function(mark)
        if mark == "'<" then return { 0, 10, 1, 0 } end
        if mark == "'>" then return { 0, 10, 10, 0 } end
        return orig_getpos(mark)
    end

    local done = h.capture_notify()
    local commands = require("opcode.commands")
    commands.send_selection(h.valid_config())

    api.append_prompt = orig_append
    proj.get_root = orig_get_root
    vim.fn.expand = orig_expand
    vim.fn.getregion = orig_getregion
    vim.fn.getpos = orig_getpos
    done()

    h.assert_notify_contains("lib/util.lua#L10-10", vim.log.levels.INFO)
end)

h.run("send_selection skips INFO notification when notify disabled", function()
    h.reset_plugin()
    package.loaded["opcode.commands"] = nil
    package.loaded["opcode.state"] = nil
    package.loaded["opcode.api"] = nil
    package.loaded["opcode.project"] = nil
    package.loaded["opcode.format"] = nil

    local sstate = require("opcode.state")
    sstate.set_selected_session("sess-abc")

    local api = require("opcode.api")
    local orig_append = api.append_prompt
    api.append_prompt = function(_, _, _, _, cb) cb(nil, {}) end

    local proj = require("opcode.project")
    local orig_get_root = proj.get_root
    proj.get_root = function() return "/proj" end

    local orig_expand = vim.fn.expand
    vim.fn.expand = function(expr)
        if expr == "%:p" then return "/proj/foo.lua" end
        return orig_expand(expr)
    end

    local orig_getregion = vim.fn.getregion
    vim.fn.getregion = function() return { "hello" } end

    local orig_getpos = vim.fn.getpos
    vim.fn.getpos = function(mark)
        if mark == "'<" then return { 0, 1, 1, 0 } end
        if mark == "'>" then return { 0, 1, 5, 0 } end
        return orig_getpos(mark)
    end

    local done = h.capture_notify()
    local commands = require("opcode.commands")
    commands.send_selection(h.valid_config({ notify = false }))

    api.append_prompt = orig_append
    proj.get_root = orig_get_root
    vim.fn.expand = orig_expand
    vim.fn.getregion = orig_getregion
    vim.fn.getpos = orig_getpos
    done()

    h.assert_no_notify(vim.log.levels.INFO)
end)

h.run("setup registers OpenCodeSendSelection command", function()
    h.reset_plugin()
    package.loaded["opcode.commands"] = nil

    require("opcode").setup(h.valid_config())

    local cmds = vim.api.nvim_get_commands({})
    assert(
       cmds["OpenCodeSendSelection"] ~= nil,
       "expected OpenCodeSendSelection command to be registered"
    )
end)

h.run("send_line errors when no session selected", function()
    h.reset_plugin()
    package.loaded["opcode.commands"] = nil
    package.loaded["opcode.state"] = nil
    package.loaded["opcode.api"] = nil
    package.loaded["opcode.project"] = nil
    package.loaded["opcode.format"] = nil

    local sstate = require("opcode.state")
    sstate.clear_selected_session()

    local done = h.capture_notify()
    local commands = require("opcode.commands")
    commands.send_line(h.valid_config())

    done()
    h.assert_notify_contains("no session", vim.log.levels.ERROR)
end)

h.run("send_line sends formatted line via append_prompt", function()
    h.reset_plugin()
    package.loaded["opcode.commands"] = nil
    package.loaded["opcode.state"] = nil
    package.loaded["opcode.api"] = nil
    package.loaded["opcode.project"] = nil
    package.loaded["opcode.format"] = nil

    local sstate = require("opcode.state")
    sstate.set_selected_session("sess-ln")

    local api = require("opcode.api")
    local orig_append = api.append_prompt
    local captured_args = {}
    api.append_prompt = function(hostname, port, session_id, text, cb)
        captured_args = { hostname = hostname, port = port, session_id = session_id, text = text }
        cb(nil, {})
    end

    local proj = require("opcode.project")
    local orig_get_root = proj.get_root
    proj.get_root = function() return "/home/user/project" end

    local orig_expand = vim.fn.expand
    vim.fn.expand = function(expr)
        if expr == "%:p" then return "/home/user/project/src/app.lua" end
        return orig_expand(expr)
    end

    local orig_get_cursor = vim.api.nvim_win_get_cursor
    vim.api.nvim_win_get_cursor = function() return { 42, 0 } end

    local orig_get_current_line = vim.api.nvim_get_current_line
    vim.api.nvim_get_current_line = function() return "local x = 1" end

    local commands = require("opcode.commands")
    commands.send_line(h.valid_config())

    api.append_prompt = orig_append
    proj.get_root = orig_get_root
    vim.fn.expand = orig_expand
    vim.api.nvim_win_get_cursor = orig_get_cursor
    vim.api.nvim_get_current_line = orig_get_current_line

    assert(captured_args.hostname == "127.0.0.1", "expected hostname 127.0.0.1")
    assert(captured_args.port == 4096, "expected port 4096")
    assert(captured_args.session_id == "sess-ln", "expected session_id sess-ln")
    assert(
        captured_args.text:find("src/app.lua#L42", 1, true),
        string.format("expected header 'src/app.lua#L42', got:\n%s", captured_args.text)
    )
    assert(
        captured_args.text:find("local x = 1", 1, true),
        string.format("expected content 'local x = 1', got:\n%s", captured_args.text)
    )
end)

h.run("send_line notifies error on API failure", function()
    h.reset_plugin()
    package.loaded["opcode.commands"] = nil
    package.loaded["opcode.state"] = nil
    package.loaded["opcode.api"] = nil
    package.loaded["opcode.project"] = nil
    package.loaded["opcode.format"] = nil

    local sstate = require("opcode.state")
    sstate.set_selected_session("sess-ln")

    local api = require("opcode.api")
    local orig_append = api.append_prompt
    api.append_prompt = function(_, _, _, _, cb)
        cb({ message = "connection refused" }, nil)
    end

    local proj = require("opcode.project")
    local orig_get_root = proj.get_root
    proj.get_root = function() return "/home/user/project" end

    local orig_expand = vim.fn.expand
    vim.fn.expand = function(expr)
        if expr == "%:p" then return "/home/user/project/foo.lua" end
        return orig_expand(expr)
    end

    local orig_get_cursor = vim.api.nvim_win_get_cursor
    vim.api.nvim_win_get_cursor = function() return { 5, 0 } end

    local orig_get_current_line = vim.api.nvim_get_current_line
    vim.api.nvim_get_current_line = function() return "print('hi')" end

    local done = h.capture_notify()
    local commands = require("opcode.commands")
    commands.send_line(h.valid_config())

    api.append_prompt = orig_append
    proj.get_root = orig_get_root
    vim.fn.expand = orig_expand
    vim.api.nvim_win_get_cursor = orig_get_cursor
    vim.api.nvim_get_current_line = orig_get_current_line
    done()

    h.assert_notify_contains("failed to send line", vim.log.levels.ERROR)
end)

h.run("send_line shows INFO notification with path on success", function()
    h.reset_plugin()
    package.loaded["opcode.commands"] = nil
    package.loaded["opcode.state"] = nil
    package.loaded["opcode.api"] = nil
    package.loaded["opcode.project"] = nil
    package.loaded["opcode.format"] = nil

    local sstate = require("opcode.state")
    sstate.set_selected_session("sess-abc")

    local api = require("opcode.api")
    local orig_append = api.append_prompt
    api.append_prompt = function(_, _, _, _, cb) cb(nil, {}) end

    local proj = require("opcode.project")
    local orig_get_root = proj.get_root
    proj.get_root = function() return "/proj" end

    local orig_expand = vim.fn.expand
    vim.fn.expand = function(expr)
        if expr == "%:p" then return "/proj/lib/util.lua" end
        return orig_expand(expr)
    end

    local orig_get_cursor = vim.api.nvim_win_get_cursor
    vim.api.nvim_win_get_cursor = function() return { 15, 0 } end

    local orig_get_current_line = vim.api.nvim_get_current_line
    vim.api.nvim_get_current_line = function() return "return true" end

    local done = h.capture_notify()
    local commands = require("opcode.commands")
    commands.send_line(h.valid_config())

    api.append_prompt = orig_append
    proj.get_root = orig_get_root
    vim.fn.expand = orig_expand
    vim.api.nvim_win_get_cursor = orig_get_cursor
    vim.api.nvim_get_current_line = orig_get_current_line
    done()

    h.assert_notify_contains("lib/util.lua#L15", vim.log.levels.INFO)
end)

h.run("send_line skips INFO notification when notify disabled", function()
    h.reset_plugin()
    package.loaded["opcode.commands"] = nil
    package.loaded["opcode.state"] = nil
    package.loaded["opcode.api"] = nil
    package.loaded["opcode.project"] = nil
    package.loaded["opcode.format"] = nil

    local sstate = require("opcode.state")
    sstate.set_selected_session("sess-abc")

    local api = require("opcode.api")
    local orig_append = api.append_prompt
    api.append_prompt = function(_, _, _, _, cb) cb(nil, {}) end

    local proj = require("opcode.project")
    local orig_get_root = proj.get_root
    proj.get_root = function() return "/proj" end

    local orig_expand = vim.fn.expand
    vim.fn.expand = function(expr)
        if expr == "%:p" then return "/proj/foo.lua" end
        return orig_expand(expr)
    end

    local orig_get_cursor = vim.api.nvim_win_get_cursor
    vim.api.nvim_win_get_cursor = function() return { 3, 0 } end

    local orig_get_current_line = vim.api.nvim_get_current_line
    vim.api.nvim_get_current_line = function() return "hello" end

    local done = h.capture_notify()
    local commands = require("opcode.commands")
    commands.send_line(h.valid_config({ notify = false }))

    api.append_prompt = orig_append
    proj.get_root = orig_get_root
    vim.fn.expand = orig_expand
    vim.api.nvim_win_get_cursor = orig_get_cursor
    vim.api.nvim_get_current_line = orig_get_current_line
    done()

    h.assert_no_notify(vim.log.levels.INFO)
end)

h.run("setup registers OpenCodeSendLine command", function()
    h.reset_plugin()
    package.loaded["opcode.commands"] = nil

    require("opcode").setup(h.valid_config())

    local cmds = vim.api.nvim_get_commands({})
    assert(
        cmds["OpenCodeSendLine"] ~= nil,
        "expected OpenCodeSendLine command to be registered"
    )
end)

h.exit()
