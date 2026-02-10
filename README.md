# blast.nvim

Neovim plugin for [Blast](https://github.com/taigrr/blast) activity tracking.

## Requirements

- Neovim 0.9+
- [blastd](https://github.com/taigrr/blastd) daemon running

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

## Project Configuration

Create a `.blast.toml` in your project root to override settings:

```toml
name = "my-project"  # Override project name
private = true       # Hide from public leaderboard
```

## How It Works

1. The plugin tracks buffer activity and text changes
2. Sessions are created per-project (detected via git or `.blast.toml`)
3. Activity is sent to the local blastd daemon via Unix socket
4. blastd syncs to the Blast server every 15 minutes

### Tracked Metrics

- Time spent per project
- Filetype breakdown
- Actions per minute (commands, edits)
- Words per minute

## Related Projects

- [blast](https://github.com/taigrr/blast) - Web dashboard and API
- [blastd](https://github.com/taigrr/blastd) - Local daemon
