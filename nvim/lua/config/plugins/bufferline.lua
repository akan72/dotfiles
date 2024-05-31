-- TODO: Remove highlighting with underling
-- TODO: Open files in nvim tree in new tab for Shift + enter vs. Enter to switch current tab
-- TODO: close last buffer when hitting x mark
-- TODO: Command + w to close tab
-- TODO: Pinned tab

local bufferline = require("bufferline")

bufferline.setup({
    highlights = {
        -- Check out other highlight groups that have to do with selected
        -- numbers_selected working
        -- TODO: Get default fg and bg used by not-selected tabs
        -- :hi BufferLine
        -- guifg=#928374 guibg=#242424

        modified = {
        },
        numbers_selected = {
            --fg = 0,
            fg = '#928374',
            bg = '#242424',
            --bg = '#282828',
        },
        buffer_selected = {
            --fg = 0,
            fg = '#282828',
            bg = '#282828',
        },
        info_diagnostic_selected = {
            --fg = 0,
            fg = '#282828',
            bg = '#282828',
        },
        diagnostic_selected = {
            --fg = 0,
            fg = '#282828',
            bg = '#282828',
        },
        tab_selected = {
            --fg = 0,
            fg = '#282828',
            bg = '#282828',
        },
        tab_separator_selected = {
            --fg = 0,
            fg = '#282828',
            bg = '#282828',
        },
        --fill = {
        --    ctermbg = '7',
        --    ctermfg = '0',
        --}
    },
    options = {
        separator_style = "slant",
        --close_command = function()
            -- TODO: close, if curent window is nvim tree and we close the current tab and there is another tab open, then switch to it
            -- If last buffer, close vim
            -- Use BufferLineCycleNext? or GotoBuffer? if # of buffers > 0. Go to last buffer
        --end,
        -- Sidebar offset for NvimTree. Show current directory
        offsets = {
            {

                filetype = "NvimTree",
                -- text = "File Explorer",
                text = function()
                    return vim.fn.getcwd()
                end,
                highlight = "Directory",
                separator = true, -- Default separator character
            }
        },
        -- Show close icon on hover
        hover = {
            enabled = true,
            delay = 0,
            reveal = {'close'}
        },
        show_tab_indicators = true,
        indicator = {
            style = 'underline',
        },
        tab_size = 10,
        -- Set number shown on buffer to be it's ordinal posiion
        numbers = function(opts)
            return string.format('%s.', opts.ordinal)
        end,
        -- Show file disagnostics (warnings errors etc.)
        diagnostics = "nvim_lsp",
        diagnostics_indicator = function(count, level, diagnostics_dict, context)
            local icon = level:match("error") and " " or " "
            return " " .. icon .. count
        end
    }
})

-- Go to buffer at ordinal index
local tab_indicies = {1, 2, 3, 4, 5, 6, 7, 8} -- 8 is lucky!
for _, index in ipairs(tab_indicies) do
    vim.keymap.set("n", "<leader>" .. index, "<Cmd>BufferLineGoToBuffer" .. index .. "<CR>", { noremap = true, silent = true})
end

-- Go to last buffer
vim.keymap.set("n", "<leader>0", "<CMD>BufferLineGoToBuffer -1<CR>", { noremap = true, silent = true})

-- Close current buffer
-- vim.keymap.set("n", "<leader>w", ":BufferLinePickClose<CR>", { noremap = true, silent = true })
-- vim.keymap.set("n", "<leader>w", ":bd<CR>:BufferLineGoToBuffer 1<CR>", { noremap = true, silent = true })

-- TODO: make into fuction and use in close_command as well
-- https://neovim.io/doc/user/lua.html#vim.cmd()
--function M.refresh()
--  vim.schedule(function() vim.cmd.redrawtabline() end)
--end
-- https://github.com/akinsho/bufferline.nvim/blob/9e8d2f695dd50ab6821a6a53a840c32d2067a78a/lua/bufferline/commands.lua#L38
-- Default highlight for bufferline
-- guifg=#ebdbb2 guibg=#282828 guisp=#3c3836
-- GruvboxBg0     xxx guifg=#282828
-- GruvboxBg1     xxx guifg=#3c3836

vim.keymap.set("n", "<leader>w", ":bp<CR> :bd#<CR>:redrawtabline<CR>", { noremap = true, silent = true })
