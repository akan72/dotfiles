-- TODO: Config
-- Make sign column match background color
vim.cmd([[highlight! link SignColumn LineNr]])
vim.api.nvim_create_autocmd("ColorScheme",  {
    pattern = "*",
    command = vim.cmd([[highlight! link signcolumn linenr]])
})

-- Set gitgutter highlight groups
vim.g.gitgutter_set_sign_backgrounds = 1

vim.api.nvim_set_hl(0, "GitGutterAdd", { fg = "#009900", ctermfg = 2 })
vim.api.nvim_set_hl(0, "GitGutterChange", { fg = "#bbbb00", ctermfg = 3 })
vim.api.nvim_set_hl(0, "GitGutterDelete", { fg = "#ff2222", ctermfg = 1 })
