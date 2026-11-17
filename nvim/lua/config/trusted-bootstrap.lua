-- Local, read-only checks run before any downloaded Lua. No shell or network.
local M = {}
-- Reviewed origins, shared with assimilate.sh: nvim/plugin-origins.json, next to
-- lua/. A null origin marks a disabled plugin that is never installed or loaded.
local nvim_dir = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(debug.getinfo(1, 'S').source:sub(2))))
local origins = vim.json.decode(table.concat(vim.fn.readfile(nvim_dir .. '/plugin-origins.json'), '\n'))
local function git(path, args)
  local command = { 'git', '-c', 'core.hooksPath=/dev/null', '-c', 'core.fsmonitor=false', '-C', path }
  vim.list_extend(command, args)
  local result = vim.fn.system(command)
  if vim.v.shell_error ~= 0 then error('Cannot verify plugin checkout: ' .. path) end
  return vim.trim(result)
end
function M.verify(path, name, commit)
  if type(origins[name]) ~= 'string' or type(commit) ~= 'string' or #commit ~= 40 or not commit:match('^[0-9a-f]+$') then
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
  for name, origin in pairs(origins) do
    if origin ~= vim.NIL and type(lock[name]) ~= 'table' then
      error('Missing active plugin lock entry: ' .. name)
    end
  end
  if lock['lazy.nvim'].commit ~= '85c7ff3711b730b4030d03144f6db6375044ae82' then
    error('Stage-zero lazy.nvim pin requires explicit review')
  end
  for name, entry in pairs(lock) do
    -- Disabled plugins are never loaded and need not be installed.
    if origins[name] ~= vim.NIL then M.verify(data .. '/lazy/' .. name, name, entry.commit) end
  end
end
return M
