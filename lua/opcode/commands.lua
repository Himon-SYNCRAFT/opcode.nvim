local M = {}
local api = require("opcode.api")
local state = require("opcode.state")
local format = require("opcode.format")
local project = require("opcode.project")
local selection = require("opcode.selection")

local function get_visual_selection(mode)
	local bufnr = 0

	local start_pos = vim.fn.getpos("'<")
	local end_pos = vim.fn.getpos("'>")

	local start_row, start_col = start_pos[2], start_pos[3]
	local end_row, end_col = end_pos[2], end_pos[3]

	-- normalize (gdy zaznaczone od dołu)
	if start_row > end_row or (start_row == end_row and start_col > end_col) then
		start_row, end_row = end_row, start_row
		start_col, end_col = end_col, start_col
	end

	local lines = {}
	local text = ""

	-- LINE-WISE
	if mode == "V" then
		lines = vim.api.nvim_buf_get_lines(bufnr, start_row - 1, end_row, false)
		text = table.concat(lines, "\n")
	end

	-- CHAR-WISE
	if mode == "v" then
		lines = vim.api.nvim_buf_get_text(bufnr, start_row - 1, start_col - 1, end_row - 1, end_col, {})
		text = table.concat(lines, "\n")
	end

	-- BLOCK-WISE
	if mode == "\22" then
		local raw = vim.api.nvim_buf_get_lines(bufnr, start_row - 1, end_row, false)

		for _, line in ipairs(raw) do
			table.insert(lines, string.sub(line, start_col, end_col))
		end

		text = table.concat(lines, "\n")
	end

	return {
		mode = mode, -- "v", "V", "\22"
		start_line = start_row, -- np. 1
		end_line = end_row, -- np. 12
		start_col = start_col,
		end_col = end_col,
		lines = lines, -- { "line1", "line2", ... }
		text = text, -- "line1\nline2"
	}
end

function M.connect(config)
	local cmd = config.command:gsub("{port}", tostring(config.port))
	vim.fn.jobstart(cmd, {
		detach = true,
	})
end

local function format_session(session)
	local datetime = os.date("%Y-%m-%d %H:%M", session.time.created / 1000)
	return string.format("[%s] %s (%s)", datetime, session.title, session.id)
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
			if not item then
				return
			end
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
	if buf_path == "" then
		return nil
	end
	local root = project.get_root(config)
	if root and buf_path:sub(1, #root) == root then
		return buf_path:sub(#root + 2)
	end
	return buf_path
end

function M.send_file(config)
	local session_id = require_session()
	if not session_id then
		return
	end

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
	if not session_id then
		return
	end

	local row = vim.api.nvim_win_get_cursor(0)[1]
	-- local content = vim.api.nvim_get_current_line()
	local content = ""

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
	if not session_id then
		return
	end

	local sel = selection.get_latest()
	if not sel then
		vim.notify("no selection", vim.log.levels.ERROR)
		return
	end

	local rel_path = relative_path(config)
	if not rel_path then
		return
	end

	local lines = vim.api.nvim_buf_get_lines(0, sel.start_line - 1, sel.end_line, false)

	-- local text = table.concat(lines, "\n")
	local text = ""

	local formatted = format.format_selection(rel_path, sel.start_line, sel.end_line, text)

	api.append_prompt(config.hostname, config.port, session_id, formatted, function(err)
		if err then
			vim.notify("send failed", vim.log.levels.ERROR)
		end
	end)
end

return M
