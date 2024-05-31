local lsp_zero = require('lsp-zero')

lsp_zero.on_attach(function(client, bufnr)
  lsp_zero.default_keymaps({buffer = bufnr})
end)

-- Disable semantic highlighting
lsp_zero.set_server_config({
  on_init = function(client)
    client.server_capabilities.semanticTokensProvider = nil
  end,
})

-- Install language servers
require('mason').setup({})
require('mason-lspconfig').setup({
  ensure_installed = {
    'lua_ls',
    'tsserver',
    'eslint',
    'jedi_language_server',
    --'pyright',
    'rust_analyzer',
  },
  handlers = {
    lsp_zero.default_setup,
  },
})

-- Configure lua language server for neovim
-- Fix Undefined global 'vim'
require('lspconfig').lua_ls.setup({
    settings = {
        Lua = {
            diagnostics = {
                globals = {'vim'}
            }
        }
    }
})

-- Suggested config https://github.com/neovim/nvim-lspconfig#suggested-configuration
-- lspconfig.pyright.setup {}
local cmp = require('cmp')
local cmp_action = require('lsp-zero').cmp_action()
--local cmp_mappings = lsp_zero.defaults.cmp_mappings({
--    -- Move forward in suggestions with Tab
--    ['<Tab>'] = cmp.mapping.select_next_item(cmp_select),
--    -- Move backwards in suggestions with Shift-Tab
--    ['<S-Tab>'] = cmp.mapping.select_prev_item(cmp_select),
--    -- Confirm suggestions with Enter
--    ['<Enter>'] = cmp.mapping.confirm({ select = true }),
--    --['<C-Space>'] = cmp.mapping.complete(),
--})

-- Set max number of autocomplete entries
cmp.setup({
    window = {
        completion = cmp.config.window.bordered(),
        documentation = cmp.config.window.bordered(),
    },
    mapping = cmp.mapping.preset.insert({
        -- Ctrl+Space to trigger completion menu
        ['<C-Space>'] = cmp.mapping.complete(),
        -- Confirm suggestions with Enter
        ['<CR>'] = cmp.mapping.confirm({ select = true }),
        -- Next suggestion with Tab
        ['<Tab>'] = cmp.mapping.select_next_item({behavior = 'select'}),
        -- Previous suggestion with Shift + Tab
        ['<S-Tab>'] = cmp.mapping.select_prev_item({behavior = 'select'}),
        -- Navigate between snippet placeholder
        ['<C-f>'] = cmp_action.luasnip_jump_forward(),
        ['<C-b>'] = cmp_action.luasnip_jump_backward(),
        -- Scroll up and down in the completion documentation
        ['<C-k>'] = cmp.mapping.scroll_docs(-4),
        ['<C-j>'] = cmp.mapping.scroll_docs(4),
        -- Move forward in suggestions with Tab
        -- ['<Tab>'] = cmp_action.luasnip_jump_forward(),
        -- Move backwards in suggestions with Shift-Tab
        --['<S-Tab>'] = cmp_action.luasnip_jump_backward(),
    }),
    performance = {
        max_view_entries = 5
    },
})


-- lsp_zero.set_server_config({
--     capabilities = cmp.core.lsp.capabilities(),
--     handlers = cmp.core.lsp.handlers(),
-- })

-- lsp.on_attach(function(client, bufnr)
--     local opts = { buffer = bufnr, remap = false }
--
--     vim.keymap.set("n", "gd", function() vim.lsp.buf.definition() end, opts)
--     vim.keymap.set("n", "K", function() vim.lsp.buf.hover() end, opts)
--     vim.keymap.set("n", "<leader>vws", function() vim.lsp.buf.workspace_symbol() end, opts)
--     vim.keymap.set("n", "<leader>vd", function() vim.diagnostic.open_float() end, opts)
--     vim.keymap.set("n", "[d", function() vim.diagnostic.goto_next() end, opts)
--     vim.keymap.set("n", "]d", function() vim.diagnostic.goto_prev() end, opts)
--     vim.keymap.set("n", "<leader>vca", function() vim.lsp.buf.code_action() end, opts)
--     vim.keymap.set("n", "<leader>vrr", function() vim.lsp.buf.references() end, opts)
--     vim.keymap.set("n", "<leader>vrn", function() vim.lsp.buf.rename() end, opts)
--     vim.keymap.set("i", "<C-h>", function() vim.lsp.buf.signature_help() end, opts)
-- end)
--
-- lsp.setup()
--
-- -- Format files
-- vim.keymap.set("n", "<leader>f", function()
--     vim.lsp.buf.format()
-- end)
