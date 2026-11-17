-- Run after the real init. Real-server checks are explicit; the native UI fixture is offline.
local root = vim.env.DOTFILES_LSP_TEST_ROOT or vim.fn.tempname()
vim.fn.mkdir(root, 'p', 448)
root = assert(vim.uv.fs_realpath(root), 'Fixture root must exist')
local results = {}
local function record(name) table.insert(results, name); print('PASS: ' .. name) end
local function wait(label, predicate, timeout)
  assert(vim.wait(timeout or 15000, predicate, 50), label .. ' timed out')
end
local function write(path, lines)
  vim.fn.mkdir(vim.fs.dirname(path), 'p', 448)
  vim.fn.writefile(lines, path)
end
local function request(client, method, position, bufnr)
  local response = client:request_sync(method, {
    textDocument = { uri = vim.uri_from_bufnr(bufnr) }, position = position,
  }, 20000, bufnr)
  assert(response and not response.err, method .. ': ' .. vim.inspect(response))
  return response.result
end

local function real_servers()
  local native = require('config.plugins.lsp')
  assert(#native.missing == 0, 'External servers missing: ' .. table.concat(native.missing, ', '))
  local fixtures = {
    { name = 'jedi_language_server', ft = 'python', file = 'python/main.py',
      lines = { 'import pathlib', 'value = pathlib.Path(".")', 'value.' },
      hover = { line = 1, character = 1 }, completion = { line = 2, character = 6 }, diagnostic = true },
    { name = 'lua_ls', ft = 'lua', file = 'lua/main.lua',
      lines = { 'local value = "hello"', 'print(value)', 'vim.print(value)', 'print(unknown_dotfiles_symbol)' },
      hover = { line = 0, character = 8 }, completion = { line = 1, character = 8 }, diagnostic = true },
    { name = 'ts_ls', ft = 'typescript', file = 'typescript/main.ts',
      lines = { 'const value: string = "hello";', 'value.', 'const wrong: number = "text";' },
      hover = { line = 0, character = 8 }, completion = { line = 1, character = 6 }, diagnostic = true },
    { name = 'eslint', ft = 'javascript', file = 'eslint/main.js',
      lines = { 'const unused = 1;', 'console.log(unknown_dotfiles_symbol);' }, diagnostic = true },
    { name = 'rust_analyzer', ft = 'rust', file = 'rust/src/main.rs',
      lines = { 'fn main() {', '    let value: i32 = 1;', '    val', '}' },
      hover = { line = 1, character = 9 }, completion = { line = 2, character = 7 } },
  }
  write(root .. '/lua/.luarc.json', { '{}' })
  write(root .. '/typescript/package.json', { '{"private":true}' })
  write(root .. '/typescript/tsconfig.json', { '{"compilerOptions":{"strict":true,"noEmit":true}}' })
  write(root .. '/eslint/package.json', { '{"private":true}' })
  write(root .. '/eslint/eslint.config.mjs', { 'export default [{rules:{"no-unused-vars":"error","no-undef":"error"}}];' })
  write(root .. '/rust/Cargo.toml', { '[package]', 'name = "dotfiles-lsp-fixture"', 'version = "0.0.0"', 'edition = "2021"' })
  for _, fixture in ipairs(fixtures) do
    local path = root .. '/' .. fixture.file
    write(path, fixture.lines)
    vim.cmd.edit(vim.fn.fnameescape(path))
    vim.bo.filetype = fixture.ft
    local bufnr = vim.api.nvim_get_current_buf()
    wait(fixture.name .. ' attach', function()
      return #vim.lsp.get_clients({ bufnr = bufnr, name = fixture.name }) > 0
    end, 30000)
    local client = vim.lsp.get_clients({ bufnr = bufnr, name = fixture.name })[1]
    wait(fixture.name .. ' initialize', function() return client.initialized end)
    assert(vim.deep_equal(client.config.cmd, native.commands[fixture.name]), 'Unexpected server command')
    assert(not table.concat(client.config.cmd, ' '):find('/mason/', 1, true), 'Mason process used')
    for _, key in ipairs({ 'gd', 'gD', 'gi', 'go', 'gr', 'K', 'gs', 'gl', '<F2>', '<F3>', '<F4>' }) do
      assert(vim.fn.maparg(key, 'n') ~= '', 'Missing preserved LSP mapping: ' .. key)
    end
    if fixture.hover then
      wait(fixture.name .. ' hover', function()
        local hover = request(client, 'textDocument/hover', fixture.hover, bufnr)
        return hover and hover.contents ~= nil
      end, 30000)
    end
    if fixture.completion then
      local response
      wait(fixture.name .. ' completion', function()
        response = request(client, 'textDocument/completion', fixture.completion, bufnr)
        return response and #(response.items or response) > 0
      end, 30000)
    end
    if fixture.diagnostic then
      wait(fixture.name .. ' diagnostics', function()
        local provider = client.server_capabilities.diagnosticProvider
        local push = vim.lsp.diagnostic.get_namespace(client.id)
        local pull = vim.lsp.diagnostic.get_namespace(client.id, true, type(provider) == 'table' and provider.identifier or nil)
        return #vim.diagnostic.get(bufnr, { namespace = push }) + #vim.diagnostic.get(bufnr, { namespace = pull }) > 0
      end, 30000)
    end
    if fixture.name == 'lua_ls' then
      for _, diagnostic in ipairs(vim.diagnostic.get(bufnr)) do
        assert(not (diagnostic.lnum == 2 and diagnostic.code == 'undefined-global'), 'Lua vim global rejected')
      end
    end
    record(fixture.name .. ': external command, attachment and language responses')
    client:stop(true)
    vim.cmd('enew!')
  end
  -- Preserve installed project libraries without selecting project server launchers.
  local project = root .. '/existing-node-project'
  write(project .. '/node_modules/typescript/lib/tsserver.js', { '// Inert presence fixture, never executed.' })
  write(project .. '/node_modules/eslint/package.json', { '{"name":"eslint"}' })
  local ts = vim.deepcopy(vim.lsp.config.ts_ls)
  ts.root_dir = project
  ts.before_init({}, ts)
  assert(ts.init_options.tsserver.path == project .. '/node_modules/typescript/lib/tsserver.js')
  assert(vim.deep_equal(ts.cmd, native.commands.ts_ls))
  local eslint = vim.deepcopy(vim.lsp.config.eslint)
  eslint.root_dir = project
  eslint.before_init({}, eslint)
  assert(eslint.settings.nodePath == project .. '/node_modules')
  assert(vim.deep_equal(eslint.cmd, native.commands.eslint))
  record('trusted project libraries preserve explicit external server commands')
end

local function transport(label, include_snippet)
  return function(dispatchers)
    local closed, id = false, 0
    return {
      is_closing = function() return closed end,
      terminate = function() closed = true; vim.schedule(function() dispatchers.on_exit(0, 0) end) end,
      notify = function() return true end,
      request = function(method, params, callback)
        id = id + 1
        local result
        if method == 'initialize' then
          result = { capabilities = { textDocumentSync = 1, hoverProvider = true,
            completionProvider = { resolveProvider = true, triggerCharacters = { '.' } } } }
        elseif method == 'textDocument/completion' then
          result = { { label = label, insertText = label } }
          if include_snippet then
            table.insert(result, { label = 'alphaSnippet', insertTextFormat = 2,
              textEdit = { range = { start = { line = 0, character = 0 }, ['end'] = { line = 0, character = 5 } },
                newText = 'call(${1:first}, ${2:second})$0' },
              documentation = { kind = 'markdown', value = string.rep('Completion documentation line.\n\n', 30) } })
          end
        elseif method == 'completionItem/resolve' then result = params
        elseif method == 'textDocument/hover' then result = { contents = 'Fixture hover' }
        end
        vim.schedule(function() callback(nil, result) end)
        return true, id
      end,
    }
  end
end

local ids, steps = {}, {}
local function input(keys) vim.api.nvim_input(keys) end
local function step(fn) table.insert(steps, fn) end
local function current_text() return vim.api.nvim_get_current_line() end
local selected_word
step(function()
  vim.cmd('enew!')
  vim.bo.filetype = 'dotfiles_native_fixture'
  for i, label in ipairs({ 'alphaOne', 'alphaTwo' }) do
    ids[i] = assert(vim.lsp.start({ name = 'dotfiles-fixture-' .. i, cmd = transport(label, i == 1), root_dir = root }))
  end
end)
step(function()
  for _, id in ipairs(ids) do assert(vim.lsp.get_client_by_id(id).initialized, 'Fixture initialization failed') end
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'alpha' })
  vim.cmd('startinsert!')
end)
step(function() assert(vim.api.nvim_get_mode().mode == 'i'); input('<C-Space>') end)
step(function()
  assert(vim.fn.pumvisible() == 1, 'Native completion menu did not open')
  local info = vim.fn.complete_info({ 'items', 'selected' })
  local labels = {}
  for _, item in ipairs(info.items) do labels[item.abbr] = (labels[item.abbr] or 0) + 1 end
  assert(labels.alphaOne == 1 and labels.alphaTwo == 1, 'Multiple clients did not merge once')
  assert(info.selected == -1, 'Menu should start without an implicit selection')
  record('native completion merges multiple clients without duplicate items')
  input('<Tab>')
end)
local first_selection
step(function()
  first_selection = vim.fn.complete_info({ 'selected' }).selected
  assert(first_selection >= 0, 'Tab did not select completion')
  input('<S-Tab>')
end)
step(function()
  assert(vim.fn.complete_info({ 'selected' }).selected ~= first_selection, 'Shift-Tab did not navigate backward')
  input('<Tab>')
end)
step(function()
  local info = vim.fn.complete_info({ 'items', 'selected' })
  assert(info.selected >= 0, 'Tab did not select completion')
  selected_word = info.items[info.selected + 1].word
  input('<CR>')
end)
step(function()
  assert(current_text() == selected_word and vim.api.nvim_buf_line_count(0) == 1, 'Enter failed to accept the selected completion')
  record('Tab selection and Enter acceptance apply a real completion edit')
  input('<Esc>')
end)
step(function()
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'alpha' })
  vim.cmd('startinsert!')
end)
step(function() input('<C-Space>') end)
step(function()
  local info = vim.fn.complete_info({ 'items' })
  local found
  for index, item in ipairs(info.items) do if item.abbr == 'alphaSnippet' then found = index end end
  assert(found, 'Snippet completion not offered')
  input(string.rep('<Tab>', found))
end)
local documentation_window, documentation_topline
step(function()
  assert(vim.fn.complete_info({ 'selected', 'items' }).selected >= 0, 'Snippet selection failed')
  documentation_window = vim.fn.complete_info().preview_winid
  assert(documentation_window and documentation_window > 0, 'Native documentation popup missing')
  documentation_topline = vim.api.nvim_win_call(documentation_window, function() return vim.fn.winsaveview().topline end)
  input('<C-j>')
end)
step(function()
  local current = vim.api.nvim_win_call(documentation_window, function() return vim.fn.winsaveview().topline end)
  assert(current > documentation_topline, 'Ctrl-j did not scroll documentation down')
  input('<C-k>')
end)
step(function()
  local current = vim.api.nvim_win_call(documentation_window, function() return vim.fn.winsaveview().topline end)
  assert(current == documentation_topline, 'Ctrl-k did not scroll documentation back up')
  record('native completion documentation scrolling keys')
  input('<CR>')
end)
local first_position
step(function()
  assert(current_text() == 'call(first, second)', 'LSP snippet was not expanded by native completion: ' .. current_text())
  assert(vim.snippet.active({ direction = 1 }), 'Native snippet not active')
  first_position = vim.api.nvim_win_get_cursor(0)[2]
  input('<C-f>')
end)
step(function()
  assert(vim.api.nvim_win_get_cursor(0)[2] > first_position, 'Ctrl-f did not move to next placeholder')
  input('<C-b>')
end)
step(function()
  assert(vim.api.nvim_win_get_cursor(0)[2] == first_position, 'Ctrl-b did not return to previous placeholder')
  record('native LSP snippet expansion and forward/backward placeholder keys')
  vim.snippet.stop()
  input('<Esc>')
end)
step(function()
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'plain' })
  vim.cmd('startinsert!')
end)
step(function() input('<CR>') end)
step(function()
  assert(vim.api.nvim_buf_line_count(0) == 2, 'Enter without selected completion did not insert newline')
  record('Enter newline fallback outside completion')
  input('<Esc>')
end)
step(function()
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'alpha' })
  vim.cmd('startinsert!')
end)
step(function() input('<C-Space>') end)
step(function()
  assert(vim.fn.pumvisible() == 1 and vim.fn.complete_info({ 'selected' }).selected == -1)
  input('<CR>')
end)
step(function()
  assert(vim.api.nvim_buf_line_count(0) == 2 and vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == 'alpha', 'Enter accepted an unselected item')
  input('<Tab>')
end)
local indent_width
step(function()
  indent_width = #current_text()
  assert(indent_width > 0 and current_text():match('^%s+$'), 'Tab editing fallback failed')
  input('<S-Tab>')
end)
step(function()
  assert(#current_text() < indent_width, 'Shift-Tab editing fallback did not outdent')
  record('unselected-menu newline and normal Tab/Shift-Tab editing fallbacks')
  input('<Esc>K')
end)
step(function()
  local floats = 0
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_config(win).relative ~= '' then floats = floats + 1; vim.api.nvim_win_close(win, true) end
  end
  assert(floats > 0, 'Hover key did not show an LSP response')
  record('hover key invokes native LSP behavior')
  for _, id in ipairs(ids) do vim.lsp.get_client_by_id(id):stop(true) end
  for _, module in ipairs({ 'cmp', 'luasnip', 'lsp-zero', 'mason', 'mason-lspconfig' }) do
    assert(not package.loaded[module], 'Retired wrapper loaded: ' .. module)
  end
  assert(vim.g.colors_name == 'gruvbox' and vim.go.loadplugins == false)
  record('real theme, disabled native package loading and retired-wrapper absence')
end)
step(function()
  local bin = root .. '/mason/bin'
  vim.fn.mkdir(bin, 'p', 448)
  for _, name in ipairs({ 'node', 'jedi-language-server', 'lua-language-server', 'typescript-language-server', 'vscode-eslint-language-server', 'rust-analyzer' }) do
    write(bin .. '/' .. name, { '#!/bin/sh', 'touch "' .. root .. '/unexpected-launch"' })
    vim.fn.setfperm(bin .. '/' .. name, 'rwx------')
  end
  vim.env.PATH = bin .. ':/usr/bin:/bin'
  package.loaded['config.plugins.lsp'] = nil
  local missing = require('config.plugins.lsp')
  assert(#missing.missing == 5 and vim.tbl_isempty(missing.commands), 'Missing/Mason server was enabled')
  assert(vim.fn.exists(':LspSetupStatus') == 2)
  assert(vim.fn.filereadable(root .. '/unexpected-launch') == 0, 'Missing-server check executed a launcher')
  record('missing/Mason servers are reported without execution or installation')
  write(root .. '/results.json', { vim.json.encode({ passed = results, count = #results }) })
  vim.cmd('qa!')
end)

local function fail(err) print(debug.traceback(tostring(err))); vim.cmd('cquit 1') end
local function begin()
  vim.o.columns, vim.o.lines = 160, 60
  vim.cmd('silent! NvimTreeClose')
  local ok, err = pcall(function() if vim.env.DOTFILES_LSP_REAL == '1' then real_servers() end end)
  if not ok then return fail(err) end
  local index = 0
  local function next_step()
    index = index + 1
    local action = steps[index]
    if not action then return end
    local passed, message = pcall(action)
    if not passed then return fail('step ' .. index .. ': ' .. tostring(message)) end
    vim.defer_fn(next_step, 300)
  end
  next_step()
end
if vim.v.vim_did_enter == 1 then vim.schedule(begin)
else vim.api.nvim_create_autocmd('VimEnter', { once = true, callback = function() vim.schedule(begin) end }) end
