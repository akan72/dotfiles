-- Local, read-only checks run before any downloaded Lua. No shell or network.
local M = {}
local origins = {
  ['Comment.nvim'] = 'numToStr/Comment.nvim', ['bufferline.nvim'] = 'akinsho/bufferline.nvim',
  ['gruvbox.nvim'] = 'ellisonleao/gruvbox.nvim', ['indent-blankline.nvim'] = 'lukas-reineke/indent-blankline.nvim',
  ['lazy.nvim'] = 'folke/lazy.nvim', ['lualine.nvim'] = 'nvim-lualine/lualine.nvim',
  ['markdown-preview.nvim'] = 'iamcco/markdown-preview.nvim',
  ['nvim-lspconfig'] = 'neovim/nvim-lspconfig',
  ['nvim-tree.lua'] = 'nvim-tree/nvim-tree.lua', ['nvim-treesitter'] = 'nvim-treesitter/nvim-treesitter',
  ['nvim-web-devicons'] = 'nvim-tree/nvim-web-devicons', ['plenary.nvim'] = 'nvim-lua/plenary.nvim',
  ['telescope.nvim'] = 'nvim-telescope/telescope.nvim', ['vim-fugitive'] = 'tpope/vim-fugitive',
  ['vim-gitgutter'] = 'airblade/vim-gitgutter',
}
local function git(path, args)
  local command = { 'git', '-c', 'core.hooksPath=/dev/null', '-c', 'core.fsmonitor=false', '-C', path }
  vim.list_extend(command, args)
  local result = vim.fn.system(command)
  if vim.v.shell_error ~= 0 then error('Cannot verify plugin checkout: ' .. path) end
  return vim.trim(result)
end
function M.verify(path, name, commit)
  if not origins[name] or type(commit) ~= 'string' or #commit ~= 40 or not commit:match('^[0-9a-f]+$') then
    error('Invalid reviewed plugin pin: ' .. tostring(name))
  end
  local uv = vim.uv or vim.loop
  local stat = uv.fs_lstat(path)
  if not stat or stat.type ~= 'directory' or uv.fs_realpath(path) ~= path then
    error('Missing or symlinked plugin: ' .. path .. '; see docs/editor-security.md')
  end
  if git(path, {'rev-parse', '--show-toplevel'}) ~= path then error('Unexpected plugin Git root: ' .. path) end
  if git(path, {'remote', 'get-url', 'origin'}) ~= 'https://github.com/' .. origins[name] .. '.git' then
    error('Unreviewed plugin origin: ' .. name)
  end
  if git(path, {'rev-parse', 'HEAD'}) ~= commit then error('Plugin differs from lazy-lock.json: ' .. name) end
  local status = git(path, {'status', '--porcelain', '--untracked-files=all', '--ignored=matching'})
  -- Help indexing creates this exact non-executable file in many locked plugins.
  if status == '?? doc/tags' or status == '!! doc/tags' then
    local tags, doc = uv.fs_lstat(path .. '/doc/tags'), uv.fs_lstat(path .. '/doc')
    local executable = tags and bit.band(tags.mode, 73) ~= 0 -- 0111
    if tags and tags.type == 'file' and not executable and doc and doc.type == 'directory' then status = '' end
  end
  if status ~= '' then error('Dirty plugin checkout: ' .. name) end
end
function M.verify_all(config, data)
  data, config = data or vim.fn.stdpath('data'), config or vim.fn.stdpath('config')
  if (vim.uv or vim.loop).fs_lstat(config .. '/plugin/packer_compiled.lua') or
     (vim.uv or vim.loop).fs_lstat(data .. '/site/pack/packer/start') then
    error('Legacy Packer state remains. Run the reversible quarantine in docs/editor-security.md')
  end
  local lock = vim.json.decode(table.concat(vim.fn.readfile(config .. '/lazy-lock.json'), '\n'))
  -- A removed lock entry must never leave an active spec unverified.
  for name, _ in pairs(origins) do
    if name ~= 'markdown-preview.nvim' and type(lock[name]) ~= 'table' then
      error('Missing active plugin lock entry: ' .. name)
    end
  end
  if lock['lazy.nvim'].commit ~= '85c7ff3711b730b4030d03144f6db6375044ae82' then
    error('Stage-zero lazy.nvim pin requires explicit review')
  end
  for name, entry in pairs(lock) do
    -- Disabled Markdown preview is never loaded and need not be installed.
    if name ~= 'markdown-preview.nvim' then M.verify(data .. '/lazy/' .. name, name, entry.commit) end
  end
end
return M
