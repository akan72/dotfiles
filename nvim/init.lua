-- Shim vim.tbl_flatten (deprecated in nvim 0.11+) until pinned plugins catch up
if vim.fn.has("nvim-0.11") == 1 then
    vim.tbl_flatten = function(t) return vim.iter(t):flatten(math.huge):totable() end
end

require("config")
