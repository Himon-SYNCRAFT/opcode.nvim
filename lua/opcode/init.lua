local M = {}

local commands = require("opcode.commands")
local _config = nil
local _setup_done = false

local function validate(config)
   if type(config.port) ~= "number" or config.port < 1 or config.port > 65535 then
      vim.notify("opcode.nvim: 'port' must be a number between 1 and 65535", vim.log.levels.ERROR)
      return false
   end
   if type(config.hostname) ~= "string" or config.hostname == "" then
      vim.notify("opcode.nvim: 'hostname' must be a non-empty string", vim.log.levels.ERROR)
      return false
   end
   if type(config.command) ~= "string" or config.command == "" then
      vim.notify("opcode.nvim: 'command' must be a non-empty string", vim.log.levels.ERROR)
      return false
   end
   if not config.command:find("{port}", 1, true) then
      vim.notify("opcode.nvim: 'command' must contain {port} placeholder", vim.log.levels.ERROR)
      return false
   end
   if config.notify ~= nil and type(config.notify) ~= "boolean" then
      vim.notify("opcode.nvim: 'notify' must be a boolean", vim.log.levels.ERROR)
      return false
   end
   if config.max_lines_in_prompt ~= nil and (type(config.max_lines_in_prompt) ~= "number" or config.max_lines_in_prompt < 1) then
      vim.notify("opcode.nvim: 'max_lines_in_prompt' must be a positive number", vim.log.levels.ERROR)
      return false
   end
   return true
end

local function check_version()
   local ver = vim.version()
   if vim.version.cmp(ver, { 0, 11 }) < 0 then
      vim.notify("opcode.nvim: requires Neovim 0.11 or later", vim.log.levels.ERROR)
      return false
   end
   return true
end

function M.setup(config)
   if _setup_done then return end
   if not check_version() then return end
   if not validate(config) then return end
   _config = config
   _config.notify = config.notify == false and false or true
   _config.max_lines_in_prompt = config.max_lines_in_prompt or 100
   _setup_done = true

   vim.api.nvim_create_user_command("OpenCodeConnect", function()
      M.connect()
   end, { desc = "Open external terminal with OpenCode" })

    vim.api.nvim_create_user_command("OpenCodeListSessions", function()
       M.list_sessions()
    end, { desc = "List and select OpenCode sessions" })

    vim.api.nvim_create_user_command("OpenCodeCreateSession", function()
        M.create_session()
    end, { desc = "Create new OpenCode session" })

     vim.api.nvim_create_user_command("OpenCodeSendFile", function()
        M.send_file()
     end, { desc = "Send current file path to OpenCode prompt" })

     vim.api.nvim_create_user_command("OpenCodeSendSelection", function()
         M.send_selection()
     end, { range = true, desc = "Send visual selection to OpenCode prompt" })

     vim.api.nvim_create_user_command("OpenCodeSendLine", function()
         M.send_line()
     end, { desc = "Send current line to OpenCode prompt" })
end

local function guard()
   if not _setup_done then
      vim.notify("opcode.nvim: call setup() before using any command", vim.log.levels.ERROR)
      return false
   end
   return true
end

function M.connect()
   if not guard() then return end
   commands.connect(_config)
end

function M.list_sessions()
   if not guard() then return end
   commands.list_sessions(_config)
end

function M.create_session()
   if not guard() then return end
   commands.create_session(_config)
end

function M.send_file()
   if not guard() then return end
   commands.send_file(_config)
end

function M.send_selection()
   if not guard() then return end
   commands.send_selection(_config)
end

function M.send_line()
    if not guard() then return end
    commands.send_line(_config)
end

return M
