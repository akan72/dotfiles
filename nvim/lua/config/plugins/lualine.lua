-- Track the last editor (non-tree) buffer so the branch component can read its
-- value when an unfocused editor pane is rendered alongside a focused NvimTree.
-- Works around lualine's branch component using globally-focused bufnr in inactive sections.
local last_editor_buf
vim.api.nvim_create_autocmd("BufEnter", {
    callback = function()
        if vim.bo.filetype ~= "NvimTree" then
            last_editor_buf = vim.api.nvim_get_current_buf()
        end
    end,
})

local function editor_branch()
    local buf = (vim.bo.filetype == "NvimTree" and last_editor_buf and vim.api.nvim_buf_is_valid(last_editor_buf))
        and last_editor_buf or vim.api.nvim_get_current_buf()
    local branch = require('lualine.components.branch.git_branch').get_branch(buf)
    if not branch or branch == '' then return '' end
    return ' ' .. branch
end

local sections = {
    lualine_a = { 'mode' },
    lualine_b = { editor_branch, 'diff', 'diagnostics' },
    lualine_c = {},                            -- removed 'filename'
    lualine_x = { 'fileformat', 'filetype' },  -- removed 'encoding'
    lualine_y = {},                            -- removed 'progress' (file %)
    lualine_z = {},                            -- removed 'location' (line:col)
}

-- Use the visual (v-block) colors for every mode so the pill color is constant
local theme = vim.deepcopy(require('lualine.themes.gruvbox_dark'))
local v = theme.visual
theme.normal, theme.insert, theme.replace, theme.command, theme.inactive = v, v, v, v, v

require('lualine').setup({
    options = {
        theme = theme,
        section_separators = { left = '', right = '' },
    },
    sections = sections,
    inactive_sections = sections,  -- keep full layout in unfocused panes (e.g. when tree is focused)
    extensions = { 'nvim-tree' },
})
