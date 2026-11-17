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
  -- Treesitter parsers and queries come only from the Neovim installation.
  assert(not package.loaded['nvim-treesitter'] and vim.fn.exists(':TSUpdate') == 0, 'Treesitter plugin loaded')
  local install = assert(vim.uv.fs_realpath(vim.env.VIMRUNTIME .. '/../../..'))
  for _, pattern in ipairs({ 'parser/*', 'queries/*/*.scm' }) do
    for _, file in ipairs(vim.api.nvim_get_runtime_file(pattern, true)) do
      assert(vim.fs.relpath(install, assert(vim.uv.fs_realpath(file))), 'Treesitter file outside Neovim: ' .. file)
    end
  end
  for _, filetype in ipairs({ 'c', 'lua', 'markdown', 'vim' }) do
    vim.cmd('enew')
    vim.bo.filetype = filetype
    assert(vim.treesitter.highlighter.active[vim.api.nvim_get_current_buf()], filetype .. ' Treesitter not started')
  end
  -- Code-fence injections run the info-string directive; the fences carry conceal_lines.
  vim.cmd('enew')
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { '# Fixture', '```python', 'value = 1', '```' })
  vim.bo.filetype = 'markdown'
  local parser = vim.treesitter.get_parser(0)
  parser:parse(true)
  local fences = {}
  for _, node, metadata in vim.treesitter.query.get('markdown', 'highlights'):iter_captures(parser:trees()[1]:root(), 0) do
    if metadata.conceal_lines then fences[node:start()] = true end
  end
  assert(fences[1] and fences[3], 'Markdown code fences are not concealed')
  if vim.env.DOTFILES_EDITOR_EXPECT_PYTHON_LSP == '1' then
    vim.cmd('enew')
    vim.api.nvim_buf_set_name(0, vim.env.DOTFILES_EDITOR_TEST_FILE)
    vim.bo.filetype = 'python'
    assert(vim.wait(15000, function()
      for _, client in ipairs(vim.lsp.get_clients({ bufnr = 0 })) do
        if client.name == 'ty' then return true end
      end
      return false
    end, 100), 'installed Python language server did not attach')
  end
end)
if not ok then print(err); vim.cmd('cquit 1') end
print('Verified live editor theme, LSP setup, bundled Treesitter and startup policy' ..
  (vim.env.DOTFILES_EDITOR_EXPECT_PYTHON_LSP == '1' and ', including Python LSP attachment' or ''))
vim.cmd('qa!')
