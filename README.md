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
use {"ninetyfive.nvim", tag = "*" }
-- dev version
use {"ninetyfive.nvim"}
```

</td>
</tr>
<tr>
<td>

[junegunn/vim-plug](https://github.com/junegunn/vim-plug)

</td>
<td>

```lua
-- stable version
Plug "ninetyfive.nvim", { "tag": "*" }
-- dev version
Plug "ninetyfive.nvim"
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

## Set up

You can tweak key mappings using `~/.config/nvim/init.vim` or `~/.vimrc` like this:

```vim
filetype plugin on

lua << EOF
require("ninetyfive").setup({
  enable_on_startup = true, -- Enable plugin on startup
  mappings = {
    enable = true,    -- Enable default keybindings
    accept = "<C-f>", -- Change default keybindings
    reject = "<C-w>", -- Change default keybindings
  }
})
EOF
```

### Lazyvim setup example:

Create a plugin directory for ninetyfive, ex: `~/.config/nvim/lua/user/plugins/ninetyfive.lua`

```lua
return {
  "https://github.com/ninetyfive-gg/ninetyfive.nvim",
  config = function()
    require("ninetyfive").setup({
      indexing = {
        mode = "on", -- enables code indexing for better completions. 'ask' by default.
        cache_consent = false -- optional, defaults to true
      }
    })
  end,
  version = false, -- we don't have versioning in the plugin yet
}
```

*Note*: all NinetyFive cache is stored at `~/.ninetyfive/`

### Pulling latest plugin code using nvim + Lazy

We don't have versioning in the plugin yet, so we need to pull the latest code using `git` and `nvim`'s built-in `git` plugin.

Run `:Lazy update ninetyfive` within neovim to pull the latest commits from main.


## Commands

| Command               | Description                    |
| --------------------- | ------------------------------ |
| `:NinetyFive`         | Enables the plugin.            |
| `:NinetyFivePurchase` | Redirects to the purchase page |
| `:NinetyFiveKey`      | Provide an API key             |

## Development

```bash
# remove old version
rm -rf ~/.config/nvim/pack/vendor/start/ninetyfive.nvim/

# copy new version
cp -r <development-directory>/ninetyfive.nvim/ ~/.config/nvim/pack/vendor/start/ninetyfive.nvim/
```