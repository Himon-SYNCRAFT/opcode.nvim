local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")
package.path = root .. "/test/?.lua;" .. root .. "/lua/?.lua;" .. root .. "/lua/?/init.lua;" .. package.path

local h = require("test_helper")
local api = require("opcode.api")

local function mock_system(response)
   local orig = vim.system
   vim.system = function(cmd, opts, on_exit)
      on_exit(response)
   end
   return function()
      vim.system = orig
   end
end

local function make_stdout(body, status)
   return body .. "\n" .. tostring(status)
end

h.run("get_project success returns parsed JSON via callback", function()
   local cleanup = mock_system({
      code = 0,
      stdout = make_stdout('{"root":"/home/user/project"}', 200),
      stderr = "",
   })

   local called = false
   local err, result
   api.get_project("127.0.0.1", 4096, function(e, r)
      called = true
      err = e
      result = r
   end)
   cleanup()

   assert(called, "callback was not called")
   assert(err == nil, string.format("expected no error, got %s", vim.inspect(err)))
   assert(
      result.root == "/home/user/project",
      string.format("expected root '/home/user/project', got %s", vim.inspect(result))
   )
end)

h.run("get_project network error calls back with error", function()
   local cleanup = mock_system({
      code = 7,
      stdout = "",
      stderr = "connection refused",
   })

   local err, result
   api.get_project("127.0.0.1", 4096, function(e, r)
      err = e
      result = r
   end)
   cleanup()

   assert(err ~= nil, "expected error, got nil")
   assert(result == nil, string.format("expected nil result, got %s", vim.inspect(result)))
   assert(
      err.message ~= nil,
      string.format("expected error with message, got %s", vim.inspect(err))
   )
   assert(err.code == 7, string.format("expected code 7, got %s", vim.inspect(err.code)))
end)

h.run("get_project JSON parse error calls back with error", function()
   local cleanup = mock_system({
      code = 0,
      stdout = make_stdout("not valid json", 200),
      stderr = "",
   })

   local err, result
   api.get_project("127.0.0.1", 4096, function(e, r)
      err = e
      result = r
   end)
   cleanup()

   assert(err ~= nil, "expected error, got nil")
   assert(result == nil, string.format("expected nil result, got %s", vim.inspect(result)))
   assert(
      err.message ~= nil,
      string.format("expected error with message, got %s", vim.inspect(err))
   )
end)

h.run("get_project HTTP error calls back with status and body", function()
   local cleanup = mock_system({
      code = 0,
      stdout = make_stdout('{"error":"not found"}', 404),
      stderr = "",
   })

   local err, result
   api.get_project("127.0.0.1", 4096, function(e, r)
      err = e
      result = r
   end)
   cleanup()

   assert(err ~= nil, "expected error, got nil")
   assert(result == nil, string.format("expected nil result, got %s", vim.inspect(result)))
   assert(err.status == 404, string.format("expected status 404, got %s", vim.inspect(err.status)))
   assert(
      err.body ~= nil,
      string.format("expected error with body, got %s", vim.inspect(err))
   )
end)

h.run("list_sessions success returns array via callback", function()
   local sessions = {
      { id = "abc123", title = "Test Session", createdAt = "2026-04-29T10:00:00Z" },
      { id = "def456", title = "Another Session", createdAt = "2026-04-29T12:00:00Z" },
   }
   local cleanup = mock_system({
      code = 0,
      stdout = make_stdout(vim.json.encode(sessions), 200),
      stderr = "",
   })

   local err, result
   api.list_sessions("127.0.0.1", 4096, function(e, r)
      err = e
      result = r
   end)
   cleanup()

   assert(err == nil, string.format("expected no error, got %s", vim.inspect(err)))
   assert(type(result) == "table", string.format("expected table, got %s", type(result)))
   assert(#result == 2, string.format("expected 2 sessions, got %d", #result))
   assert(result[1].id == "abc123", string.format("expected id 'abc123', got %s", vim.inspect(result[1].id)))
end)

h.run("create_session success POSTs title and returns id", function()
   local cleanup = mock_system({
      code = 0,
      stdout = make_stdout('{"id":"sess-new123"}', 200),
      stderr = "",
   })

   local err, result
   api.create_session("127.0.0.1", 4096, "My New Session", function(e, r)
      err = e
      result = r
   end)
   cleanup()

   assert(err == nil, string.format("expected no error, got %s", vim.inspect(err)))
   assert(
      result.id == "sess-new123",
      string.format("expected id 'sess-new123', got %s", vim.inspect(result))
   )
end)

h.run("append_prompt success POSTs session_id and text", function()
   local cleanup = mock_system({
      code = 0,
      stdout = make_stdout("true", 201),
      stderr = "",
   })

   local err, result
   api.append_prompt("127.0.0.1", 4096, "sess-abc", "hello world", function(e, r)
      err = e
      result = r
   end)
   cleanup()

   assert(err == nil, string.format("expected no error, got %s", vim.inspect(err)))
   assert(result ~= nil, "expected result, got nil")
end)

h.exit()
