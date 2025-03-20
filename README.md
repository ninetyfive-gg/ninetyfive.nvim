# ninetyfive.nvim

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

## Set up
You can tweak key mappings using `init.vim`.
```vim
filetype plugin on

lua << EOF
require("ninetyfive").setup({
  enable_on_startup = true,
  mappings = {
    accept = "<C-f>",
    reject = "<C-w>",
  }
})
EOF
```

## Commands

| Command       | Description         |
| ------------- | ------------------- |
| `:Ninetyfive` | Enables the plugin. |
