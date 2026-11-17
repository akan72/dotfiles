-- Run after the real init; optional Python LSP check uses a temporary .py buffer.
local ok, err = pcall(function()
  local config = require('lazy.core.config')
  assert(config.plugins['gruvbox.nvim'], 'lazy did not initialize plugin specs')
  assert(package.loaded['gruvbox'] and vim.g.colors_name == 'gruvbox', 'theme was not loaded')
  local lsp = require('config.plugins.lsp')
  assert(type(lsp.commands) == 'table', 'Native LSP configuration was not loaded')
  for _, name in ipairs({ 'lsp-zero', 'mason', 'mason-lspconfig', 'cmp', 'luasnip' }) do
    assert(not package.loaded[name], 'Retired wrapper loaded: ' .. name)
  end
  assert(config.options.install.missing == false and not config.options.checker.enabled,
    'startup installers or update checking enabled')
  assert(vim.go.loadplugins == false, 'native automatic loading must remain disabled after lazy setup')
  assert(vim.go.packpath == vim.env.VIMRUNTIME, 'native package path was not restricted')
  if vim.env.DOTFILES_EDITOR_EXPECT_PYTHON_LSP == '1' then
    vim.cmd('enew')
    vim.api.nvim_buf_set_name(0, vim.env.DOTFILES_EDITOR_TEST_FILE)
    vim.bo.filetype = 'python'
    assert(vim.wait(15000, function()
      for _, client in ipairs(vim.lsp.get_clients({ bufnr = 0 })) do
        if client.name == 'jedi_language_server' then return true end
      end
      return false
    end, 100), 'installed Python language server did not attach')
  end
end)
if not ok then print(err); vim.cmd('cquit 1') end
print('Verified live editor theme, LSP setup and startup policy' ..
  (vim.env.DOTFILES_EDITOR_EXPECT_PYTHON_LSP == '1' and ', including Python LSP attachment' or ''))
vim.cmd('qa!')
