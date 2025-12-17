# ninetyfive.nvim

> Repo based on [shortcut's boilerplate](https://github.com/shortcuts/neovim-plugin-boilerplate)

Very fast autocomplete

</div>

## Installation

<div align="center">
<table>
<thead>
<tr>
<th>Package manager</th>
<th>Snippet</th>
</tr>
</thead>
<tbody>
<tr>
<td>

[wbthomason/packer.nvim](https://github.com/wbthomason/packer.nvim)

</td>
<td>

```lua
-- stable version
use {"ninetyfive-gg/ninetyfive.nvim", tag = "*" }
-- dev version
use {"ninetyfive-gg/ninetyfive.nvim"}
```

</td>
</tr>
<tr>
<td>

[junegunn/vim-plug](https://github.com/junegunn/vim-plug)

</td>
<td>

```vim
" stable version
Plug "ninetyfive-gg/ninetyfive.nvim", { "tag": "*" }
" dev version
Plug "ninetyfive-gg/ninetyfive.nvim"
```

</td>
</tr>
<tr>
<td>

[folke/lazy.nvim](https://github.com/folke/lazy.nvim)

</td>
<td>

```lua
-- stable version
require("lazy").setup({{"ninetyfive-gg/ninetyfive.nvim", version = "*"}})
-- dev version
require("lazy").setup({"ninetyfive-gg/ninetyfive.nvim"})
```

</td>
</tr>
</tbody>
</table>
</div>

## Dependencies

There is a [websocket adapter](https://github.com/kevmo314/go-ws-proxy) shipped in `dist/` for all platforms.
If you do not wish to run untrusted binaries, you can delete the `dist/` directory entirely. In that case,
we will fall back to `libcurl` via LuaJIT FFI when available and `curl` CLI if it's not available. For best
results:

- Linux: make sure `libcurl.so` is installed (most distros ship it).
- macOS: use a modern libcurl (e.g., via Homebrew); the system one is often old.
- Windows: if no system libcurl is found, the plugin will fall back to a bundled/installed `curl` executable.

## Configuration

### Configuration Options

All available configuration options with their default values:

```lua
require("ninetyfive").setup({
  -- Prints useful logs about what events are triggered, and reasons actions are executed
  debug = false,

  -- When `true`, enables the plugin on NeoVim startup
  enable_on_startup = true,

  -- When `true`, disables 'ghost text' suggestions from NinetyFive
  use_cmp = false,

  -- Update server URI, mostly for debugging
  server = "wss://api.ninetyfive.gg",

  -- Key mappings configuration
  mappings = {
    -- When `true`, creates all the mappings set
    enabled = true,
    -- Sets a global mapping to accept a suggestion
    accept = "<Tab>",
    -- Sets a global mapping to accept the next word
    accept_word = "<C-h>",
    -- Sets a global mapping to accept the next line
    accept_line = "<C-j>",
    -- Sets a global mapping to reject a suggestion
    reject = "<C-w>",
  },

  -- Code indexing configuration for better completions
  indexing = {
    -- Possible values: "ask" | "on" | "off"
    -- "ask" - prompt user for permission to index code
    -- "on" - automatically index code
    -- "off" - disable code indexing
    mode = "ask",
    -- Whether to cache the user's answer per project
    cache_consent = true,
  },
})
```

### Setup Examples

#### Using [wbthomason/packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "ninetyfive-gg/ninetyfive.nvim",
  tag = "*", -- use stable version
  config = function()
    require("ninetyfive").setup({
      enable_on_startup = true,
      mappings = {
        enabled = true,
        accept = "<Tab>",
        accept_word = "<C-h>",
        accept_line = "<C-j>",
        reject = "<C-w>",
      },
      indexing = {
        mode = "ask",
        cache_consent = true,
      },
    })
  end,
}
```

#### Using [junegunn/vim-plug](https://github.com/junegunn/vim-plug)

Add to your `~/.config/nvim/init.vim` or `~/.vimrc`:

```vim
Plug 'ninetyfive-gg/ninetyfive.nvim', { 'tag': '*' }

" After plug#end(), add the setup configuration
lua << EOF
require("ninetyfive").setup({
  enable_on_startup = true,
  mappings = {
    enabled = true,
    accept = "<Tab>",
    accept_word = "<C-h>",
    accept_line = "<C-j>",
    reject = "<C-w>",
  },
  indexing = {
    mode = "ask",
    cache_consent = true,
  },
})
EOF
```

#### Using [folke/lazy.nvim](https://github.com/folke/lazy.nvim)

Update your lazy config (generally in `~/.config/nvim/init.lua`) or create a plugin file (e.g., `~/.config/nvim/lua/plugins/ninetyfive.lua`):

```lua
return {
  "ninetyfive-gg/ninetyfive.nvim",
  version = "*", -- use stable version, or `false` for dev version
  config = function()
    require("ninetyfive").setup({
      enable_on_startup = true,
      debug = false,
      server = "wss://api.ninetyfive.gg",
      mappings = {
        enabled = true,
        accept = "<Tab>",
        accept_word = "<C-h>",
        accept_line = "<C-j>",
        reject = "<C-w>",
      },
      indexing = {
        mode = "ask",
        cache_consent = true,
      },
    })
  end,
}
```

_Note_: all NinetyFive cache is stored at `~/.ninetyfive/`


#### Using NinetyFive as a `nvim-cmp` source

Add NinetyFive as a source to your cmp config:

```lua
cmp.setup({
    sources = cmp.config.sources({
      { name = "ninetyfive" },
    }),
})
```

Additionally, you can disable inline suggestions in NinetyFive's setup:
```lua
require("ninetyfive").setup({
    use_cmp = true
})
```

## Commands

| Command               | Description                                  |
| --------------------- | -------------------------------------------- |
| `:NinetyFive`         | Toggles the plugin (for the current session) |
| `:NinetyFivePurchase` | Redirects to the purchase page               |
| `:NinetyFiveKey`      | Provide an API key                           |

## Lualine Integration

NinetyFive provides a [lualine](https://github.com/nvim-lualine/lualine.nvim) component:

```lua
require("lualine").setup({
  sections = {
    lualine_x = { "ninetyfive" },
  },
})
```

The status shows your subscription name when connected, or "NinetyFive Disconnected" when offline. Colors indicate connection state (red = disconnected, yellow = free tier).

Options:

```lua
lualine_x = {
  {
    "ninetyfive",
    short = false,       -- use "95" instead of full status text
    show_colors = true,
    colors = {
      disconnected = "#e06c75",
      unpaid = "#e5c07b",
    },
  },
}
```

## Development

```bash
# remove old version
rm -rf ~/.config/nvim/pack/vendor/start/ninetyfive.nvim/

# copy new version
cp -r <development-directory>/ninetyfive.nvim/ ~/.config/nvim/pack/vendor/start/ninetyfive.nvim/
```
