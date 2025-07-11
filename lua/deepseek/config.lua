local M = {}
-- 默认配置
M.defaults = {
	enabled = true,
	window = {
		width = 80,
		height = 40,
		split_ratio = 0.2,
	},
	keymaps = {
		open_chat = "<leader>dc",
		submit = "<C-Enter>",
	},
}

M.config = {}

return M
