-- This locked release uses the configs module. Existing parsers keep highlighting.
require("nvim-treesitter.configs").setup {
    ensure_installed = {},
    highlight = { enable = true },
    sync_install = false,
    auto_install = false,
}
