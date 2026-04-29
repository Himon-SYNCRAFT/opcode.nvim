local M = {}
local api = require("opcode.api")
local state = require("opcode.state")
local format = require("opcode.format")
local project = require("opcode.project")

function M.connect(config)
   local cmd = config.command:gsub("{port}", tostring(config.port))
   vim.system(cmd, {}, function(obj)
      if obj.code ~= 0 then
         vim.notify(
            "opcode.nvim: failed to launch terminal: " .. (obj.stderr or ""),
            vim.log.levels.ERROR
         )
      end
   end)
end

local function format_session(session)
   local date, time = session.createdAt:match("^(%d%d%d%d%-%d%d%-%d%d)T(%d%d:%d%d)")
   return string.format("[%s %s] %s (%s)", date, time, session.title, session.id)
end

function M.list_sessions(config)
   api.list_sessions(config.hostname, config.port, function(err, sessions)
      if err then
         vim.notify("opcode.nvim: failed to fetch sessions", vim.log.levels.ERROR)
         return
      end

      local items = {}
      for _, s in ipairs(sessions) do
         table.insert(items, format_session(s))
      end
      table.insert(items, "[+] Create new session")

      vim.ui.select(items, { prompt = "OpenCode Sessions" }, function(item, idx)
         if not item then return end
         if idx == #items then
            state.set_selected_session("__create_new__")
         else
            state.set_selected_session(sessions[idx].id)
         end
      end)
   end)
end

local function default_title()
   local cwd = vim.fn.getcwd()
   return vim.fn.fnamemodify(cwd, ":t")
end

function M.create_session(config, title)
   title = title or default_title()
   api.create_session(config.hostname, config.port, title, function(err, result)
      if err then
         vim.notify("opcode.nvim: failed to create session", vim.log.levels.ERROR)
         return
      end
      state.set_selected_session(result.id)
      vim.notify(
         string.format("opcode.nvim: created session '%s' (%s)", result.title, result.id),
         vim.log.levels.INFO
      )
   end)
end

local function require_session()
    local session_id = state.get_selected_session()
    if not session_id then
        vim.notify("opcode.nvim: no session selected", vim.log.levels.ERROR)
        return nil
    end
    return session_id
end

local function relative_path(config)
    local buf_path = vim.fn.expand("%:p")
    if buf_path == "" then return nil end
    local root = project.get_root(config)
    if root and buf_path:sub(1, #root) == root then
        return buf_path:sub(#root + 2)
    end
    return buf_path
end

function M.send_file(config)
    local session_id = require_session()
    if not session_id then return end

    local rel_path = relative_path(config)
    if not rel_path then
        vim.notify("opcode.nvim: no file in current buffer", vim.log.levels.ERROR)
        return
    end

    local text = format.format_file(rel_path)

    api.append_prompt(config.hostname, config.port, session_id, text, function(err, _)
        if err then
            vim.notify("opcode.nvim: failed to send file path", vim.log.levels.ERROR)
            return
        end
        if config.notify ~= false then
            vim.notify("opcode.nvim: sent " .. rel_path, vim.log.levels.INFO)
        end
    end)
end

function M.send_line(config)
    local session_id = require_session()
    if not session_id then return end

    local row = vim.api.nvim_win_get_cursor(0)[1]
    local content = vim.api.nvim_get_current_line()

    local rel_path = relative_path(config)
    if not rel_path then
        vim.notify("opcode.nvim: no file in current buffer", vim.log.levels.ERROR)
        return
    end

    local text = format.format_line(rel_path, row, content)

    api.append_prompt(config.hostname, config.port, session_id, text, function(err, _)
        if err then
            vim.notify("opcode.nvim: failed to send line", vim.log.levels.ERROR)
            return
        end
        if config.notify ~= false then
            vim.notify("opcode.nvim: sent " .. rel_path .. "#L" .. row, vim.log.levels.INFO)
        end
    end)
end

function M.send_selection(config)
    local session_id = require_session()
    if not session_id then return end

    local start_pos = vim.fn.getpos("'<")
    local end_pos = vim.fn.getpos("'>")
    local lines = vim.fn.getregion(start_pos, end_pos)
    if not lines or #lines == 0 then
        vim.notify("opcode.nvim: no selection", vim.log.levels.ERROR)
        return
    end

    local rel_path = relative_path(config)
    if not rel_path then
        vim.notify("opcode.nvim: no file in current buffer", vim.log.levels.ERROR)
        return
    end

    local start_line = start_pos[2]
    local end_line = end_pos[2]
    local content = table.concat(lines, "\n")
    local text = format.format_selection(rel_path, start_line, end_line, content)

    api.append_prompt(config.hostname, config.port, session_id, text, function(err, _)
        if err then
            vim.notify("opcode.nvim: failed to send selection", vim.log.levels.ERROR)
            return
        end
        if config.notify ~= false then
            vim.notify("opcode.nvim: sent " .. rel_path .. "#L" .. start_line .. "-" .. end_line, vim.log.levels.INFO)
        end
    end)
end

return M
