-- Colorscheme config
local gruvbox = require("gruvbox").setup({
    -- Turn off Italics for strings and comments
    italic = {
        strings = false,
        comments = false,
    },
})

vim.o.background = "dark"
vim.cmd([[colorscheme gruvbox]])

-- Make sign column match bg color
vim.cmd([[
    highlight! link SignColumn Normal
]])
