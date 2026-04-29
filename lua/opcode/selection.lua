local M = {}

M.state = {
	latest = nil,
}

-- private: compute selection
local function get_selection()
	local mode = vim.api.nvim_get_mode().mode

	if not (mode == "v" or mode == "V" or mode == "\22") then
		return nil
	end

	local anchor = vim.fn.getpos("v")
	local cursor = vim.api.nvim_win_get_cursor(0)

	local sr, sc = anchor[2], anchor[3]
	local er, ec = cursor[1], cursor[2] + 1

	if sr > er or (sr == er and sc > ec) then
		sr, er = er, sr
		sc, ec = ec, sc
	end

	return {
		start_line = sr,
		end_line = er,
		start_col = sc,
		end_col = ec,
	}
end

-- public: start tracking
function M.start()
	local group = vim.api.nvim_create_augroup("opcode.selection", { clear = true })

	vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "ModeChanged" }, {
		group = group,
		callback = function()
			local sel = get_selection()
			if sel then
				M.state.latest = sel
			end
		end,
	})
end

function M.get_latest()
	return M.state.latest
end

function M.clear()
	M.state.latest = nil
end

return M
