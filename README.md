# blast.nvim

Neovim plugin for [NvimBlast](https://nvimblast.com) activity tracking.

## Requirements

- Neovim 0.9+
- [glaze.nvim](https://github.com/taigrr/glaze.nvim) manages the `blastd` binary automatically (which itself depends on `go`)

## Installation

### lazy.nvim

```lua
{
  "taigrr/blast.nvim",
  dependencies = { "taigrr/glaze.nvim" },
  event = "VeryLazy",
  opts = {
    -- socket_path = vim.fn.expand("~/.local/share/blastd/blastd.sock"),
    -- idle_timeout = 120,
    -- debug = false,
  },
}
```

### packer.nvim

```lua
use {
  "taigrr/blast.nvim",
  requires = { "taigrr/glaze.nvim" },
  config = function()
    require("blast").setup()
  end,
}
```

After installing, run `:GlazeInstall blastd` to install the daemon (or it will be installed automatically on first use if glaze.nvim is configured with `auto_install = true`).

Alternatively, install blastd manually:

```sh
go install github.com/taigrr/blastd@latest
```

## Commands

- `:BlastPing` - Ping the blastd daemon
- `:BlastStatus` - Show current tracking status
- `:BlastSync` - Trigger immediate sync to Blast server

## Project Configuration

Create a `.blast.toml` anywhere in your project tree:

```toml
# Override the project name (default: git directory name)
name = "my-project"

# Mark as private — activity is still synced, but project name and git branch/remote
# are replaced with "private" so the server only sees time, filetype, and metrics
private = true
```

The file is discovered by walking up from the current buffer's directory to the nearest git root. Both fields are optional.

### Monorepos

In a monorepo, you can place `.blast.toml` in any subdirectory to give it a distinct project name or mark it as private.
The closest `.blast.toml` between the file and the git root wins:

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

## Private mode

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

## Health Check

Run `:checkhealth blast` to verify your setup:

- Neovim version
- glaze.nvim availability
- blastd binary installation
- Socket connection status

## Related Projects

- [blastd](https://github.com/taigrr/blastd) - Local daemon
- [glaze.nvim](https://github.com/taigrr/glaze.nvim) - Go binary manager for Neovim
