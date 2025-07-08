local M = {}

-- 默认配置
local defaults = {
	enabled = true,
	-- 添加窗口相关配置
	window = {
		width = 80,
		height = 20,
	},

	-- 快捷键
	keymaps = {
		open_chat = "<leader>dc",
	},
}

function M.setup(opts)
	-- 合并默认配置和用户配置
	M.config = vim.tbl_deep_extend("force", defaults, opts or {})

	-- 如果插件被禁用则返回
	if not M.config.enabled then
		vim.notify("My LazyVim 插件已禁用")
		return
	end

	-- 设置快捷键
	M.setup_keymaps()

	-- 在这里添加你的插件逻辑
	vim.notify("My LazyVim 插件已加载!")
end

-- 设置快捷键函数
function M.setup_keymaps()
	vim.keymap.set("n", M.config.keymaps.open_chat, function()
		M.open_chat_window()
	end, { desc = "打开 DeepSeek 聊天窗口" })
end

-- 打开聊天窗口
function M.open_chat_window()
	-- 创建一个新的浮动窗口
	local chat_buf = vim.api.nvim_create_buf(false, true)

	-- 设置窗口选项
	local opts = {
		relative = "editor",
		width = M.config.window.width,
		height = M.config.window.height,
		col = (vim.o.columns - M.config.window.width) / 2,
		row = (vim.o.lines - M.config.window.height) / 2,
		style = "minimal",
		border = "single",
	}

	-- 创建窗口
	local win = vim.api.nvim_open_win(chat_buf, true, opts)

	-- 配置窗口
	vim.api.nvim_buf_set_option(chat_buf, "filetype", "markdown")
	vim.api.nvim_buf_set_option(chat_buf, "modifiable", false)
	vim.api.nvim_buf_set_option(chat_buf, "number", false)
	vim.api.nvim_buf_set_option(chat_buf, "relativenumber", false)
	vim.api.nvim_buf_set_option(chat_buf, "wrap", true)

	-- 输入窗口映射
	vim.api.nvim_buf_set_keymap(
		chat_buf,
		"n",
		"<Esc>",
		"<cmd>q!<CR>",
		{ noremap = true, silent = true, nowait = true, desc = "关闭 DeepSeek 聊天窗口" }
	)
	vim.api.nvim_buf_set_keymap(
		chat_buf,
		"n",
		"q",
		"<cmd>q!<CR>",
		{ noremap = true, silent = true, nowait = true, desc = "关闭 DeepSeek 聊天窗口" }
	)

	vim.api.nvim_create_autocmd("BufWipeout", {
		buffer = chat_buf,
		callback = function()
			if vim.api.nvim_win_is_valid(win) then
				vim.api.nvim_win_close(win, true)
			end
		end,
	})

	return {
		win = win,
		buf = chat_buf,
	}
end

return M
