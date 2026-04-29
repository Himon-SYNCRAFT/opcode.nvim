# CONTEXT

## Project: opcode.nvim

Neovim plugin for communicating with OpenCode server via HTTP REST API.

---

## Glossary

| Term | Definition |
|------|------------|
| **OpenCode Server** | HTTP server exposing OpenCode functionality via REST API (default port 4096). |
| **Session** | Conversation context in OpenCode. Plugin stores `session_id` locally after user selection. |
| **Root Project** | Base directory for relative paths. Obtained from `/project/current` API, fallback to CWD. |
| **Selection** | Text selected in Visual mode, sent with file path and line range. |
| **Line** | Cursor position in Normal mode, sent with file path and line number. |
| **Prompt** | Input field in OpenCode TUI. Plugin appends context via `append-prompt` endpoint. |

---

## Decisions from Design Session

### Connection Mode
**Plugin connects to existing server, does not manage server lifecycle.**
User runs OpenCode in external terminal, plugin communicates via HTTP to `hostname:port`.

### Configuration
```lua
require('opcode').setup({
  port = 4096,                    -- OpenCode server port
  hostname = '127.0.0.1',         -- OpenCode server host
  command = 'alacritty -e opencode --port {port}',  -- Terminal command template
  notify = true,                  -- Show error notifications
  max_lines_in_prompt = 100,      -- Max lines to include in selection payload
})
```

### Commands
| Vim Command | Lua Function | Purpose |
|-------------|--------------|---------|
| `:OpenCodeConnect` | `connect()` | Open terminal with OpenCode |
| `:OpenCodeListSessions` | `list_sessions()` | Select session via `vim.ui.select` |
| `:OpenCodeSendFile` | `send_file()` | Send relative path to current file |
| `:OpenCodeSendSelection` | `send_selection()` | Send selection with path#L5-9 and code block |
| `:OpenCodeSendLine` | `send_line()` | Send cursor line with path#L7 and code block |

### Path Handling
- Root obtained from `GET /project/current`, fallback to `.git` search, fallback to CWD.
- Always relative to root: `folder/file.php` or `../../api.json`.
- On API error: fallback to absolute path.

### Payload Formats

**File only:**
```
folder/file.php
```

**Selection:**
```
folder/file.php#L5-9
```python
def example():
    pass
```
```

**Line:**
```
folder/file.php#L7
```python
print("hello")
```
```

### Architecture
- Neovim 0.11+ required
- Async HTTP via `vim.system()` + `curl` (no external deps)
- Modular structure: `lua/opcode/{init,api,commands,util}.lua`
- No auth in MVP
- No auto-focus after send

---

## API Endpoints Used

| Method | Endpoint | Purpose |
|--------|----------|---------|
| GET | `/project/current` | Get project root |
| GET | `/session` | List all sessions |
| POST | `/tui/append-prompt` | Append text to TUI prompt |
