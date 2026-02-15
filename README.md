# blast.nvim

Neovim plugin for [Blast](https://github.com/taigrr/blast) activity tracking.

## Requirements

- Neovim 0.9+
- [blastd](https://github.com/taigrr/blastd) installed in PATH (auto-started by the plugin if not running)

## Installation

### lazy.nvim

```lua
{
  "taigrr/blast.nvim",
  event = "VeryLazy",
  opts = {
    -- socket_path = "~/.local/share/blastd/blastd.sock",
    -- idle_timeout = 120,
    -- debug = false,
  },
}
```

### packer.nvim

```lua
use {
  "taigrr/blast.nvim",
  config = function()
    require("blast").setup()
  end,
}
```

## Configuration

```lua
require("blast").setup({
  -- Path to blastd socket
  socket_path = "~/.local/share/blastd/blastd.sock",

  -- Seconds of inactivity before ending a session
  idle_timeout = 120,

  -- Debounce activity events (ms)
  debounce_ms = 1000,

  -- Enable debug logging
  debug = false,
})
```

## Commands

- `:BlastStatus` - Show current tracking status
- `:BlastPing` - Ping the blastd daemon
- `:BlastSync` - Trigger immediate sync to Blast server

## Project Configuration

Create a `.blast.toml` anywhere in your project tree:

```toml
# Override the project name (default: git directory name)
name = "my-project"

# Mark as private — activity is still synced, but project name and git remote
# are replaced with "private" so the server only sees time, filetype, and metrics
private = true
```

The file is discovered by walking up from the current buffer's directory to the nearest git root. Both fields are optional.

### Monorepos

In a monorepo, you can place `.blast.toml` in any subdirectory to give it a distinct project name or mark it as private. The closest `.blast.toml` between the file and the git root wins:

```
monorepo/               ← git root
├── .blast.toml         ← name = "monorepo" (fallback)
├── apps/
│   ├── web/
│   │   └── .blast.toml ← name = "web"
│   └── api/
│       └── .blast.toml ← name = "api", private = true
└── packages/
    └── shared/         ← inherits "monorepo" from root .blast.toml
```

For global privacy (all projects), set `metrics_only = true` in your [blastd config](https://github.com/taigrr/blastd#privacy) or `BLAST_METRICS_ONLY=true`.

## How It Works

1. The plugin tracks buffer activity and text changes
2. Sessions are created per-project (detected via git or `.blast.toml`)
3. Activity is sent to the local blastd daemon via Unix socket
4. blastd syncs to the Blast server every 10 minutes

### Tracked Metrics

- Time spent per project
- Filetype breakdown
- Actions per minute (commands, edits)
- Words per minute

## Related Projects

- [blast](https://github.com/taigrr/blast) - Web dashboard and API
- [blastd](https://github.com/taigrr/blastd) - Local daemon
