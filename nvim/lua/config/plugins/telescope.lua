local builtin = require('telescope.builtin')

-- Only files tracked by git
vim.keymap.set('n', '<C-p>', builtin.git_files, {})

-- All project files
vim.keymap.set('n', '<leader>pf', builtin.find_files, {})

-- Search project
vim.keymap.set('n', '<leader>ps', function()
	builtin.grep_string({ search = vim.fn.input("Grep > ") });
end)

-- Open help_tags
vim.keymap.set('n', '<leader>vh', builtin.help_tags, {})
