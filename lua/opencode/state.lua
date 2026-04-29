local M = {}

local _selected_session_id = nil

function M.get_selected_session()
   return _selected_session_id
end

function M.set_selected_session(id)
   _selected_session_id = id
end

function M.clear_selected_session()
   _selected_session_id = nil
end

return M
