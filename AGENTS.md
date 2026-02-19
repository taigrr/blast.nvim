# AGENTS.md

Guide for AI agents working in the blast.nvim codebase.

## Project Overview

blast.nvim is a Neovim plugin that tracks coding activity (time, filetypes, APM, WPM) and sends it to a local [blastd](https://github.com/taigrr/blastd) daemon via Unix socket. The daemon syncs data to the [Blast](https://github.com/taigrr/blast) web dashboard.

**Requirements**: Neovim 0.9+, [glaze.nvim](https://github.com/taigrr/glaze.nvim) (optional, for binary management), blastd daemon (auto-installed via glaze or manually).

## Commands

There are no build, test, or lint commands configured for this project. No Makefile, CI workflows, or linting/formatting configs exist.

To manually test, install the plugin in Neovim and run:

- `:BlastStatus` — show socket connection and session info
- `:BlastPing` — ping the blastd daemon
- `:BlastSync` — trigger an immediate sync to the Blast server (rate-limited to 10 per 10 minutes)

## Code Organization

```
plugin/
  blast.lua          # Entry point: guard + user command registration
lua/blast/
  init.lua           # Public API: setup(), status(), ping(); holds config; setup guard; glaze registration
  socket.lua         # Unix socket client (async connect, send JSON, ping, keepalive, auto-start blastd)
  tracker.lua        # Autocommand-based activity tracking + session management with debounce
  utils.lua          # Filesystem helpers: project detection, file search, exec (cross-platform)
  health.lua         # Health check module (:checkhealth blast)
```

This follows the standard Neovim plugin layout:

- `plugin/` runs on load (guarded by `vim.g.loaded_blast`)
- `lua/blast/` is the module, loaded on demand via `require("blast")`

## Architecture

### Data Flow

1. **Autocommands** in `tracker.lua` fire on buffer/text/command events
2. **Tracker** manages sessions (start/end) and computes metrics (APM, WPM) with debounced word counting
3. **Socket** sends JSON-newline-delimited messages to blastd via `vim.uv` pipes with async connect
4. **Keepalive** pings blastd every 10 seconds to prevent the daemon's 5-minute idle auto-shutdown
5. **Auto-start**: If blastd's socket file doesn't exist, the plugin spawns blastd automatically
6. **Utils** resolves the current project from `.blast.toml` or git, with caching

### Configuration

Defaults in `init.lua`:

| Key            | Default                             | Purpose                                  |
| -------------- | ----------------------------------- | ---------------------------------------- |
| `socket_path`  | `~/.local/share/blastd/blastd.sock` | Unix socket to blastd                    |
| `idle_timeout` | `120`                               | Seconds before ending an idle session    |
| `debounce_ms`  | `1000`                              | Debounce interval for word count updates |
| `debug`        | `false`                             | Enable `vim.notify` debug messages       |

Users pass overrides to `require("blast").setup(opts)`. Config is merged with `vim.tbl_deep_extend("force", ...)`.

### Session Lifecycle

- **Start**: On `BufEnter`/`BufWritePost` when project changes or no session exists
- **End**: On idle timeout (`idle_timeout` seconds) or `VimLeavePre`
- **Minimum duration**: Sessions shorter than 10 seconds are silently discarded
- **Project detection**: `.blast.toml` name field > git directory name > parent directory name
- **WPM tracking**: Word count deltas are accumulated per session (only positive deltas counted), debounced to avoid per-keystroke full buffer scans

### Socket Protocol

Messages are JSON objects terminated by `\n`, sent over a Unix domain socket. Two message types:

- `{ "type": "ping" }` — health check / keepalive
- `{ "type": "activity", "data": { ... } }` — session activity report
- `{ "type": "sync" }` — trigger immediate sync (response includes `ok`, `error`, `message` fields)

Activity data includes: `project`, `git_remote`, `started_at`, `ended_at` (ISO 8601 UTC), `filetype`, `actions_per_minute`, `words_per_minute`, `editor` (always `"neovim"`).

### Keepalive & Auto-start

- **Keepalive**: `socket.lua` runs a `uv.new_timer()` that sends `{"type": "ping"}` every 10 seconds while connected. This prevents blastd from auto-shutting down due to client inactivity.
- **Auto-start**: On connect, if the socket file doesn't exist, the plugin checks for `blastd` in PATH and spawns it as a detached process. It waits up to 500ms for the socket file to appear before connecting.
- **Shutdown**: On `VimLeavePre`, the tracker ends the session. The keepalive timer and socket are cleaned up. If this was the last client, blastd will auto-shutdown after 5 minutes of no events.

## Code Patterns and Conventions

### Module Structure

Every module follows the same pattern:

```lua
local M = {}
-- local state at module scope
function M.setup(cfg) ... end
-- public functions
return M
```

### Neovim API Usage

- Uses `vim.uv` with `vim.loop` fallback for libuv bindings (`local uv = vim.uv or vim.loop`)
- Buffer options accessed via `vim.bo[bufnr]` indexing
- Autocommands grouped under `BlastTracker` augroup with `clear = true`
- Timers use `uv.new_timer()` with `vim.schedule_wrap()` callbacks (not `vim.defer_fn`)
- User notifications via `vim.notify` with appropriate `vim.log.levels`
- Lazy `require()` in `init.lua` — socket and tracker are loaded inside `setup()`, not at module scope

### Error Handling

- Socket errors are caught with `pcall`, logged only when `debug = true`
- Failed socket connections cause the client to close and nil out
- `send()` auto-reconnects on each call if not connected
- Non-file buffers are silently skipped (`buftype ~= ""` or empty name)
- `end_session()` captures session data into a local before nilling `current_session`, so deferred callbacks don't reference nil

### Caching

- `utils.lua` caches project info per directory in a module-local table (`project_cache`)
- Cache is never invalidated (assumes project identity doesn't change during a session)

### Timers

- `idle_timer` and `debounce_timer` use `uv.new_timer()`, reused across resets (stop + start) to avoid allocating new handles
- `ping_timer` runs every 10 seconds for keepalive, started in `setup()`, stopped on shutdown
- All timer callbacks use `vim.schedule_wrap()` to safely call Neovim APIs from libuv threads

## Adding New Features

- **New tracked events**: Add autocommands in `tracker.setup()`, update metrics in the module-local variables, include new fields in the `activity` table sent from `end_session()`
- **New user commands**: Register in `plugin/blast.lua`, implement in `lua/blast/init.lua`
- **New socket message types**: For fire-and-forget messages, add a method in `socket.lua` following the `send_activity` pattern. For request-response messages (like sync), use the `request()` method which opens a dedicated connection and invokes a callback with the parsed response
- **New config options**: Add defaults in `M.config` in `init.lua`, access via `config` locals passed through `setup()`

## Glaze Integration

The plugin registers `blastd` with [glaze.nvim](https://github.com/taigrr/glaze.nvim) at module load time (before `setup()` is called):

```lua
local _glaze_ok, _glaze = pcall(require, "glaze")
if _glaze_ok then
  _glaze.register("blastd", "github.com/taigrr/blastd", {
    plugin = "blast.nvim",
  })
end
```

This allows users to install/update blastd via `:GlazeInstall blastd` or `:GlazeUpdate blastd`. The registration is optional — if glaze.nvim is not installed, the plugin falls back to expecting blastd in PATH.

## Health Check

Run `:checkhealth blast` to verify:

- Neovim version (>= 0.9)
- glaze.nvim availability (optional, shows warning if missing)
- blastd binary installation (error if missing, suggests `:GlazeInstall blastd`)
- Socket connection status (info only)
