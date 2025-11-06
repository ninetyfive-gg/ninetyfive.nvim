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

This module uses native `curl`. Ensure curl is installed on your system before installing the plugin.

## Configuration

### Configuration Options

All available configuration options with their default values:

```lua
require("ninetyfive").setup({
  -- Prints useful logs about what events are triggered, and reasons actions are executed
  debug = false,

  -- When `true`, enables the plugin on NeoVim startup
  enable_on_startup = true,

  -- Update server URI, mostly for debugging
  server = "wss://api.ninetyfive.gg",

  -- Key mappings configuration
  mappings = {
    -- When `true`, creates all the mappings set
    enabled = true,
    -- Sets a global mapping to accept a suggestion
    accept = "<Tab>",
    -- Sets a global mapping to accept a suggestion and edit
    accept_edit = "<C-g>",
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
        accept_edit = "<C-g>",
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
    accept_edit = "<C-g>",
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

Create a plugin file (e.g., `~/.config/nvim/lua/plugins/ninetyfive.lua`):

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
        accept_edit = "<C-g>",
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

### Pulling latest plugin code using nvim + Lazy

We don't have versioning in the plugin yet, so we need to pull the latest code using `git` and `nvim`'s built-in `git` plugin.

Run `:Lazy update ninetyfive` within neovim to pull the latest commits from main.

## Commands

| Command               | Description                                  |
| --------------------- | -------------------------------------------- |
| `:NinetyFive`         | Toggles the plugin (for the current session) |
| `:NinetyFivePurchase` | Redirects to the purchase page               |
| `:NinetyFiveKey`      | Provide an API key                           |

## Development

```bash
# remove old version
rm -rf ~/.config/nvim/pack/vendor/start/ninetyfive.nvim/

# copy new version
cp -r <development-directory>/ninetyfive.nvim/ ~/.config/nvim/pack/vendor/start/ninetyfive.nvim/
```
