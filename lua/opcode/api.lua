local M = {}

local function request(method, url, body, callback)
   local cmd = { "curl", "-s", "-S", "-w", "\n%{http_code}" }
   if method == "POST" then
      vim.list_extend(cmd, { "-H", "Content-Type: application/json" })
      vim.list_extend(cmd, { "-d", vim.json.encode(body) })
   end
   vim.list_extend(cmd, { url })

   vim.system(cmd, {}, function(obj)
      if obj.code ~= 0 then
         return callback({ message = "Network error", code = obj.code, stderr = obj.stderr })
      end

      local stdout = obj.stdout
      local last_nl = stdout:reverse():find("\n", 1, true)
      local status_str, body_str
      if last_nl then
         local idx = #stdout - last_nl + 1
         status_str = stdout:sub(idx + 1)
         body_str = stdout:sub(1, idx - 1)
      else
         status_str = stdout
         body_str = ""
      end

      local status = tonumber(status_str)
      if not status or status < 200 or status >= 300 then
         return callback({ message = "HTTP error", status = status, body = body_str })
      end

      local ok, data = pcall(vim.json.decode, body_str)
      if not ok then
         return callback({ message = "JSON parse error", details = data })
      end

      callback(nil, data)
   end)
end

function M.get_project(hostname, port, callback)
   local url = string.format("http://%s:%d/project/current", hostname, port)
   request("GET", url, nil, callback)
end

function M.list_sessions(hostname, port, callback)
   local url = string.format("http://%s:%d/session", hostname, port)
   request("GET", url, nil, callback)
end

function M.create_session(hostname, port, title, callback)
   local url = string.format("http://%s:%d/session", hostname, port)
   request("POST", url, { title = title }, callback)
end

function M.append_prompt(hostname, port, session_id, text, callback)
   local url = string.format("http://%s:%d/tui/append-prompt", hostname, port)
   request("POST", url, { sessionId = session_id, text = text }, callback)
end

return M
