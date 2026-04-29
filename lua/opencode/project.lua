local M = {}

local function find_git_root(buf_dir)
   local dir = buf_dir
   while dir ~= "/" and dir ~= "" do
      if vim.fn.isdirectory(dir .. "/.git") == 1 then
         return dir
      end
      dir = vim.fn.fnamemodify(dir, ":h")
   end
   return nil
end

local function try_api_root(config)
   if not config or not config.hostname or not config.port then
      return nil
   end
   local url = string.format("http://%s:%d/project/current", config.hostname, config.port)
   local ok, result = pcall(function()
      return vim.system({ "curl", "-s", "-m", "2", url }):wait()
   end)
   if not ok then
      vim.notify("opencode.nvim: project API request failed", vim.log.levels.WARN)
      return nil
   end
   if result.code ~= 0 then
      vim.notify("opencode.nvim: project API returned non-zero exit", vim.log.levels.WARN)
      return nil
   end
   local decode_ok, data = pcall(vim.json.decode, result.stdout)
   if not decode_ok or not data or not data.root then
      vim.notify("opencode.nvim: project API response invalid", vim.log.levels.WARN)
      return nil
   end
   return data.root
end

function M.get_root(config)
   local api_root = try_api_root(config)
   if api_root then return api_root end

   local buf_dir = vim.fn.expand("%:p:h")
   if buf_dir and buf_dir ~= "" then
      local git_root = find_git_root(buf_dir)
      if git_root then return git_root end
   end
   return vim.fn.getcwd()
end

return M
