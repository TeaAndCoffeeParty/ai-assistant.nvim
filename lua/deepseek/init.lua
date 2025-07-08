local M = {}
local window = require("deepseek.window")

-- 默认配置
local defaults = {
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
		M.open_chat_ui()
	end, { desc = "打开 DeepSeek 聊天窗口" })
end

-- 打开聊天窗口
function M.open_chat_ui()
	local win_state = window.create(M.config.window)

	M.setup_buffers(win_state)

	vim.api.nvim_set_current_win(win_state.input_win)
	vim.cmd("startinsert!")
end

function M.setup_buffers(state)
	-- 输入缓冲区设置
	vim.api.nvim_buf_set_option(state.input_buf, "filetype", "markdown")
	vim.api.nvim_buf_set_option(state.input_buf, "modifiable", true)
	vim.api.nvim_buf_set_option(state.input_buf, "buftype", "")
	vim.api.nvim_buf_set_option(state.input_buf, "number", false)
	vim.api.nvim_buf_set_option(state.input_buf, "relativenumber", false)
	vim.api.nvim_buf_set_option(state.input_buf, "wrap", true)

	-- 输出缓冲区设置
	vim.api.nvim_buf_set_option(state.output_buf, "filetype", "markdown")
	vim.api.nvim_buf_set_option(state.output_buf, "modifiable", true)
	vim.api.nvim_buf_set_option(state.input_buf, "buftype", "nofile")
	vim.api.nvim_buf_set_option(state.output_buf, "number", false)
	vim.api.nvim_buf_set_option(state.output_buf, "relativenumber", false)
	vim.api.nvim_buf_set_option(state.output_buf, "wrap", true)

	-- 设置初始内容
	vim.api.nvim_buf_set_lines(state.input_buf, 0, -1, false, { "" })
	vim.api.nvim_buf_set_lines(state.output_buf, 0, -1, false, { "等待您的问题..." })

	vim.api.nvim_buf_set_option(state.output_buf, "modifiable", false)
	vim.api.nvim_buf_set_option(state.output_buf, "readonly", true)

	-- 输入窗口映射
	vim.api.nvim_buf_set_keymap(
		state.input_buf,
		"n",
		"<Esc>",
		"<cmd>lua require('deepseek').close_windows()<CR>",
		{ noremap = true, silent = true, nowait = true, desc = "关闭聊天窗口" }
	)
	vim.api.nvim_buf_set_keymap(
		state.input_buf,
		"n",
		"<leader>ds",
		"<cmd>lua require('deepseek').submit_input()<CR>",
		{ noremap = true, silent = true, nowait = true, desc = "提交输入" }
	)
end

function M.close_windows()
	window.close()
end

function M.submit_input()
	local state = window.get_state()
	-- 获取输入内容
	local input_lines = vim.api.nvim_buf_get_lines(state.input_buf, 0, -1, false)

	-- 有一行有效数据就算有效
	local has_content = false
	for _, line in ipairs(input_lines) do
		if line ~= "" then
			has_content = true
			break
		end
	end

	if not has_content then
		vim.notify("请输入有效内容", vim.log.levels.WARN)
		return
	end

	local output_content = {
		"> " .. input_lines[1],
	}
	for i = 2, #input_lines do
		table.insert(output_content, input_lines[i])
	end
	table.insert(output_content, "")
	table.insert(output_content, "------------------")
	table.insert(output_content, "这是模拟回复 - 实际使用时这里会是 API 返回的内容")
	table.insert(output_content, "当前时间：" .. os.date("%Y-%m-%d %H:%M:%S"))

	--临时允许输出缓冲区修改
	vim.api.nvim_buf_set_option(state.output_buf, "modifiable", true)
	vim.api.nvim_buf_set_option(state.output_buf, "readonly", false)
	-- 模拟回复
	vim.api.nvim_buf_set_lines(state.output_buf, 0, -1, false, output_content)

	vim.api.nvim_buf_set_option(state.output_buf, "modifiable", false)
	vim.api.nvim_buf_set_option(state.output_buf, "readonly", true)

	--清空输入区
	vim.api.nvim_buf_set_lines(state.input_buf, 0, -1, false, { "" })
	vim.api.nvim_win_set_cursor(state.input_win, { 1, 0 })
end

return M
