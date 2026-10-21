#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
tmp="$(mktemp -d /private/tmp/editor-policy.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT
checkout="$tmp/plugin"
git init -q "$checkout"
git -C "$checkout" remote add origin https://github.com/folke/lazy.nvim.git
printf 'fixture\n' > "$checkout/file"
git -C "$checkout" add file
git -C "$checkout" -c user.name=Fixture -c user.email=fixture@example.invalid -c commit.gpgsign=false commit -qm fixture
sha="$(git -C "$checkout" rev-parse HEAD)"
cat > "$tmp/test.lua" <<'LUA'
local root, fixture, sha = arg[1], arg[2], arg[3]
package.path = root .. '/nvim/lua/?.lua;' .. package.path
local policy = require('config.trusted-bootstrap')
local function good() policy.verify(fixture, 'lazy.nvim', sha) end
local function bad(fn)
  local ok = pcall(fn)
  assert(not ok, 'Verification should have refused this fixture')
end
good()
bad(function() policy.verify(fixture, 'lazy.nvim', string.rep('0', 40)) end)
bad(function() policy.verify(fixture, 'lazy.nvim', 'malformed') end)
bad(function() policy.verify(fixture .. '-missing', 'lazy.nvim', sha) end)
vim.fn.writefile({'unreviewed'}, fixture .. '/untracked.lua')
bad(good)
vim.fn.delete(fixture .. '/untracked.lua')
vim.fn.writefile({'ignored.lua', 'doc/tags'}, fixture .. '/.git/info/exclude')
vim.fn.writefile({'unreviewed ignored code'}, fixture .. '/ignored.lua')
bad(good)
vim.fn.delete(fixture .. '/ignored.lua')
vim.fn.mkdir(fixture .. '/doc')
vim.fn.writefile({'help index only'}, fixture .. '/doc/tags')
good()
vim.fn.setfperm(fixture .. '/doc/tags', 'rwx------')
bad(good)
vim.fn.setfperm(fixture .. '/doc/tags', 'rw-------')
good()
vim.fn.delete(fixture .. '/doc/tags')
vim.fn.system({'ln', '-s', fixture .. '/file', fixture .. '/doc/tags'})
bad(good)
vim.fn.delete(fixture .. '/doc/tags')
vim.fn.writefile({'changed'}, fixture .. '/file')
bad(good)
vim.fn.system({'git', '-C', fixture, 'checkout', '--', 'file'})
vim.fn.system({'git', '-C', fixture, 'remote', 'set-url', 'origin', 'https://example.invalid/wrong.git'})
bad(good)
vim.fn.system({'git', '-C', fixture, 'remote', 'set-url', 'origin', 'https://github.com/folke/lazy.nvim.git'})
vim.fn.system({'ln', '-s', fixture, fixture .. '-link'})
bad(function() policy.verify(fixture .. '-link', 'lazy.nvim', sha) end)
good()
-- Removing an active lock entry must fail before any plugin verification/loading.
local config = fixture .. '-config'
vim.fn.mkdir(config)
local lock = vim.json.decode(table.concat(vim.fn.readfile(root .. '/nvim/lazy-lock.json'), '\n'))
lock['Comment.nvim'] = nil
vim.fn.writefile({vim.json.encode(lock)}, config .. '/lazy-lock.json')
local verify, checked = policy.verify, 0
policy.verify = function() checked = checked + 1 end
bad(function() policy.verify_all(config, fixture .. '-data') end)
assert(checked == 0, 'Incomplete lock must fail before visiting downloaded checkouts')
-- Legacy executable state must fail before touching any downloaded checkout.
local legacy = fixture .. '-legacy-config'
local data = fixture .. '-legacy-data'
vim.fn.mkdir(legacy .. '/plugin', 'p')
vim.fn.writefile({ 'error("legacy loader must never execute")' }, legacy .. '/plugin/packer_compiled.lua')
bad(function() policy.verify_all(legacy, data) end)
assert(checked == 0)
vim.fn.delete(legacy .. '/plugin/packer_compiled.lua')
vim.fn.mkdir(data .. '/site/pack/packer/start', 'p')
bad(function() policy.verify_all(legacy, data) end)
assert(checked == 0)
policy.verify = verify
-- The pinned Treesitter release exposes configs.setup, not the top-level setup.
local ts
package.loaded['nvim-treesitter.configs'] = { setup = function(opts) ts = opts end }
dofile(root .. '/nvim/lua/config/plugins/nvim-treesitter.lua')
assert(ts.highlight.enable and ts.auto_install == false and #ts.ensure_installed == 0)
print('Editor origin/HEAD/dirty/symlink gates and Treesitter API checks passed')
vim.cmd('qa!')
LUA
NVIM_LOG_FILE="$tmp/nvim.log" XDG_STATE_HOME="$tmp/state" nvim --headless -u NONE -i NONE --noplugin -l "$tmp/test.lua" "$repo_root" "$checkout" "$sha"
python3 - "$repo_root" <<'PY'
import pathlib,sys
r=pathlib.Path(sys.argv[1])
s=(r/'nvim/lua/config/plugins.lua').read_text()
for forbidden in ['git", "clone', 'mkdp#util#install', 'MasonUpdate', "nvim-treesitter.install"]:
    assert forbidden not in s, forbidden
assert s.index('verify_all()') < s.index('vim.go.loadplugins = true') < s.index('require("lazy")')
assert 'vim.go.packpath = vim.env.VIMRUNTIME' in s
for control in ['missing = false', 'local_spec = false', 'checker = { enabled = false }', 'rocks = { enabled = false }', 'pkg = { enabled = false }']:
    assert control in s, control
assert 'vim.go.loadplugins = false' in (r/'nvim/init.lua').read_text()
lsp=(r/'nvim/lua/config/plugins/lsp.lua').read_text()
for control in ['vim.lsp.config(name, config)', 'vim.lsp.enable(name)', 'vim.lsp.completion.enable', 'vim.snippet.active', 'vim.snippet.jump', "RUSTUP_AUTO_INSTALL = '0'", "CARGO_NET_OFFLINE = 'true'"]:
    assert control in lsp, control
for removed in ['lsp-zero', 'mason-lspconfig', "require('mason')", "require('cmp')", "require('luasnip')"]:
    assert removed not in s and removed not in lsp, removed
lock=__import__('json').loads((r/'nvim/lazy-lock.json').read_text())
for removed in ['lsp-zero.nvim', 'mason.nvim', 'mason-lspconfig.nvim', 'nvim-cmp', 'cmp-nvim-lsp', 'LuaSnip']:
    assert removed not in lock, removed
zsh=(r/'zshrc').read_text()
assert 'DISABLE_AUTO_UPDATE="true"' in zsh
assert 'export ZSH_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/oh-my-zsh"' in zsh
assert zsh.index('export ZSH_CACHE_DIR=') < zsh.index('source $ZSH/oh-my-zsh.sh')
print('Editor no-startup-installer policy assertions passed')
PY
