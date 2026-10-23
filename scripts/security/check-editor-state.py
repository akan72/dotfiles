#!/usr/bin/env python3
"""Read-only plugin policy verification; does not source the editor init/plugins."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

repo = Path(__file__).resolve().parents[2]
nvim = shutil.which('nvim')
if not nvim:
    sys.exit('Neovim is absent; install the reviewed version before checking editor state')
# Argument arrays and Lua JSON string literals keep paths separate from code.
command = ('package.path = ' + json.dumps(str(repo / 'nvim/lua/?.lua') + ';') + ' .. package.path; '
           'require("config.trusted-bootstrap").verify_all(' + json.dumps(str(repo / 'nvim')) + '); '
           'print("Editor plugin origin, commit and clean-state checks passed")')
result = subprocess.run([nvim, '--headless', '-u', 'NONE', '-i', 'NONE', '--noplugin',
                         '-c', 'lua local ok, err = pcall(function() ' + command + ' end); '
                         'if not ok then print(err); vim.cmd("cquit 1") end', '-c', 'qa!'],
                        timeout=90, env={**os.environ, "NVIM_LOG_FILE": "/dev/null"})
sys.exit(result.returncode)
