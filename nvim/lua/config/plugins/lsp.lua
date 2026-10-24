-- Native LSP/completion/snippets. Installation is an explicit external setup step.
local M = { commands = {}, missing = {} }
local uv = vim.uv
local group = vim.api.nvim_create_augroup('DotfilesLsp', { clear = true })
local mason = vim.fs.normalize(vim.fn.stdpath('data') .. '/mason')

local function executable(name)
  local path = vim.fn.exepath(name)
  local real = path ~= '' and uv.fs_realpath(path) or nil
  -- Never silently keep using a retired Mason server or rustup's auto-install proxy.
  if not real or path:find('/mason/bin/', 1, true) or real:find('/mason/packages/', 1, true) or
     vim.fs.relpath(mason, vim.fs.normalize(path)) or
     vim.fs.relpath(mason, real) or vim.fs.basename(real) == 'rustup' then
    return nil
  end
  return real
end

local function completion_key(key, fallback)
  if vim.fn.pumvisible() == 1 then return key end
  return fallback
end

local function snippet_key(direction, fallback)
  if vim.snippet.active({ direction = direction }) then
    return '<Cmd>lua vim.snippet.jump(' .. direction .. ')<CR>'
  end
  return fallback
end

local function scroll_docs(lines, fallback)
  local win = vim.fn.complete_info().preview_winid
  if not win or win == 0 or not vim.api.nvim_win_is_valid(win) then return fallback end
  vim.schedule(function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_call(win, function()
        local key = lines > 0 and '<C-e>' or '<C-y>'
        vim.cmd.normal({ args = { math.abs(lines) .. vim.api.nvim_replace_termcodes(key, true, false, true) }, bang = true })
      end)
    end
  end)
  return ''
end

vim.opt.completeopt = { 'menu', 'menuone', 'noselect', 'popup' }
vim.opt.pumheight = 5
vim.keymap.set('i', '<C-Space>', function()
  if #vim.lsp.get_clients({ bufnr = 0, method = 'textDocument/completion' }) > 0 then
    vim.lsp.completion.get()
  end
end, { desc = 'LSP completion' })
vim.keymap.set('i', '<CR>', function()
  if vim.fn.pumvisible() == 1 then
    if vim.fn.complete_info({ 'selected' }).selected >= 0 then return '<C-y>' end
    return '<C-e><CR>'
  end
  return '<CR>'
end, { expr = true, desc = 'Accept selected completion or insert newline' })
vim.keymap.set('i', '<Tab>', function() return completion_key('<C-n>', '<Tab>') end, { expr = true })
vim.keymap.set('i', '<S-Tab>', function() return completion_key('<C-p>', '<C-d>') end, { expr = true })
vim.keymap.set({ 'i', 's' }, '<C-f>', function() return snippet_key(1, '<C-f>') end, { expr = true })
vim.keymap.set({ 'i', 's' }, '<C-b>', function() return snippet_key(-1, '<C-b>') end, { expr = true })
vim.keymap.set('i', '<C-k>', function() return scroll_docs(-4, '<C-k>') end, { expr = true })
vim.keymap.set('i', '<C-j>', function() return scroll_docs(4, '<C-j>') end, { expr = true })

vim.api.nvim_create_autocmd('LspAttach', {
  group = group,
  callback = function(event)
    local client = vim.lsp.get_client_by_id(event.data.client_id)
    if not client then return end
    vim.lsp.semantic_tokens.enable(false, { bufnr = event.buf, client_id = client.id })
    if client:supports_method('textDocument/completion', event.buf) then
      -- Native completion merges supported clients into one per-buffer controller.
      vim.lsp.completion.enable(true, client.id, event.buf, { autotrigger = true })
    end
    local function map(mode, key, action, desc)
      -- Preserve existing user mappings.
      for _, m in ipairs(type(mode) == 'table' and mode or { mode }) do
        if vim.fn.maparg(key, m) == '' then
          vim.keymap.set(m, key, action, { buffer = event.buf, desc = desc })
        end
      end
    end
    map('n', 'gd', vim.lsp.buf.definition, 'LSP definition')
    map('n', 'gD', vim.lsp.buf.declaration, 'LSP declaration')
    map('n', 'gi', vim.lsp.buf.implementation, 'LSP implementation')
    map('n', 'go', vim.lsp.buf.type_definition, 'LSP type definition')
    map('n', 'gr', vim.lsp.buf.references, 'LSP references')
    map('n', 'K', vim.lsp.buf.hover, 'LSP hover')
    map('n', 'gs', vim.lsp.buf.signature_help, 'LSP signature help')
    map('n', 'gl', vim.diagnostic.open_float, 'Line diagnostics')
    map('n', '<F2>', vim.lsp.buf.rename, 'LSP rename')
    map({ 'n', 'x' }, '<F3>', function() vim.lsp.buf.format({ async = true }) end, 'LSP format')
    map({ 'n', 'x' }, '<F4>', vim.lsp.buf.code_action, 'LSP code actions')
    map('n', '[d', function() vim.diagnostic.jump({ count = -1 }) end, 'Previous diagnostic')
    map('n', ']d', function() vim.diagnostic.jump({ count = 1 }) end, 'Next diagnostic')
  end,
})

local node = executable('node')
local servers = {
  { 'jedi_language_server', 'jedi-language-server', {}, {
      init_options = { diagnostics = { enable = true } },
    } },
  { 'lua_ls', 'lua-language-server', {}, {
      settings = { Lua = { diagnostics = { globals = { 'vim' } }, telemetry = { enable = false } } },
    } },
  { 'ts_ls', 'typescript-language-server', { '--stdio' }, {
      init_options = {
        disableAutomaticTypingAcquisition = true,
        tsserver = { path = vim.fn.expand('~/.local/share/dotfiles-lsp/node/node_modules/typescript/lib/tsserver.js') },
      },
      before_init = function(_, config)
        local project = config.root_dir and vim.fs.joinpath(config.root_dir, 'node_modules/typescript/lib/tsserver.js')
        if project and uv.fs_stat(project) then config.init_options.tsserver.path = project end
      end,
    } },
  { 'eslint', 'vscode-eslint-language-server', { '--stdio' }, {
      settings = { nodePath = vim.fn.expand('~/.local/share/dotfiles-lsp/node/node_modules') },
      -- Keep workspace settings without lspconfig's implicit `yarn exec` PnP wrapper.
      before_init = function(_, config)
        if config.root_dir then
          config.settings.workspaceFolder = { uri = vim.uri_from_fname(config.root_dir), name = vim.fs.basename(config.root_dir) }
          local modules = vim.fs.joinpath(config.root_dir, 'node_modules')
          if uv.fs_stat(modules .. '/eslint/package.json') then config.settings.nodePath = modules end
        end
      end,
    } },
  { 'rust_analyzer', 'rust-analyzer', {}, {
      cmd_env = { RUSTUP_AUTO_INSTALL = '0', CARGO_NET_OFFLINE = 'true' },
      settings = { ['rust-analyzer'] = {
        cargo = { offline = true, buildScripts = { enable = false } },
        procMacro = { enable = false },
        checkOnSave = false,
      } },
      -- Find the workspace without executing upstream's online cargo/root probe.
      root_dir = function(bufnr, on_dir)
        local root = vim.fs.root(bufnr, { 'Cargo.toml', 'rust-project.json', '.git' })
        if not root then return end
        local analyzer = executable('rust-analyzer')
        local cargo = analyzer and vim.fs.joinpath(vim.fs.dirname(analyzer), 'cargo') or nil
        if not cargo or vim.fn.executable(cargo) ~= 1 or not uv.fs_stat(root .. '/Cargo.toml') then
          on_dir(root)
          return
        end
        vim.system({ cargo, 'metadata', '--offline', '--no-deps', '--format-version', '1', '--manifest-path', root .. '/Cargo.toml' },
          { text = true, env = { RUSTUP_AUTO_INSTALL = '0', CARGO_NET_OFFLINE = 'true' } }, function(result)
            vim.schedule(function()
              local ok, data = pcall(vim.json.decode, result.stdout or '')
              on_dir(result.code == 0 and ok and data.workspace_root or root)
            end)
          end)
      end,
    } },
}

for _, server in ipairs(servers) do
  local name, binary, args, config = unpack(server)
  local path = executable(binary)
  if (name == 'ts_ls' or name == 'eslint') and not node then path = nil end
  if path then
    -- Explicit commands prevent project-local or Mason launchers from taking over.
    local cmd = (name == 'ts_ls' or name == 'eslint') and { node, path } or { path }
    vim.list_extend(cmd, args)
    config.cmd = cmd
    vim.lsp.config(name, config)
    vim.lsp.enable(name)
    M.commands[name] = cmd
  else
    vim.lsp.enable(name, false)
    table.insert(M.missing, binary)
  end
end

vim.api.nvim_create_user_command('LspSetupStatus', function()
  local lines = { 'External language servers (no startup installation):' }
  for _, server in ipairs(servers) do
    local name = server[1]
    table.insert(lines, name .. ': ' .. (M.commands[name] and table.concat(M.commands[name], ' ') or
      'missing external executable; see docs/editor-security.md'))
  end
  vim.notify(table.concat(lines, '\n'), vim.log.levels.INFO)
end, { desc = 'Show external LSP commands and missing-server setup guidance' })
if #M.missing > 0 then
  vim.schedule(function()
    vim.notify('Optional LSP tools missing: ' .. table.concat(M.missing, ', ') .. '. Run :LspSetupStatus for setup guidance.', vim.log.levels.WARN)
  end)
end
return M
