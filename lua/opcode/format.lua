local M = {}

local function detect_lang(path)
   local ext = path:match("%.(%w+)$")
   if not ext then return "" end
   local map = {
      lua = "lua",
      py = "python",
      js = "javascript",
      ts = "typescript",
      rs = "rust",
      go = "go",
      java = "java",
      c = "c",
      cpp = "cpp",
      h = "c",
      hpp = "cpp",
      rb = "ruby",
      php = "php",
      sh = "sh",
      bash = "bash",
      zsh = "zsh",
      html = "html",
      css = "css",
      json = "json",
      yaml = "yaml",
      yml = "yaml",
      toml = "toml",
      md = "markdown",
      sql = "sql",
      vim = "vim",
   }
   return map[ext] or ""
end

local function code_block(lang, content)
   return string.format("```%s\n%s\n```", lang, content)
end

function M.format_file(path)
   return path
end

function M.format_selection(path, start_line, end_line, content)
   local header = string.format("%s#L%d-%d", path, start_line, end_line)
   return header .. "\n" .. code_block(detect_lang(path), content)
end

function M.format_line(path, line, content)
   local header = string.format("%s#L%d", path, line)
   return header .. "\n" .. code_block(detect_lang(path), content)
end

return M
