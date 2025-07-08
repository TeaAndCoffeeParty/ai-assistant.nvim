local M = {}

-- 默认配置
local defaults = {
	enabled = true,
	window = {
		width = 80,
		height = 20,
		split_ratio = 0.4,
	},
	keymaps = {
		open_chat = "<leader>dc",
		submit = "<C-Enter>",
	},
}

-- 保存窗口和缓冲区引用
local state = {
	input_win = nil,
	output_win = nil,
	input_buf = nil,
	output_buf = nil,
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
	-- 如果窗口已经存在，则聚焦到输入窗口
	if state.input_win and vim.api.nvim_win_is_valid(state.input_win) then
		vim.api.nvim_set_current_win(state.input_win)
		return
	end

	-- 创建两个缓冲区
	state.input_buf = vim.api.nvim_create_buf(false, true)
	state.output_buf = vim.api.nvim_create_buf(false, true)

	local total_height = M.config.window.height
	local input_height = math.floor(total_height * M.config.window.split_ratio)
	local output_height = total_height - input_height - 1

	state.input_win = vim.api.nvim_open_win(state.input_buf, true, {
		width = M.config.window.width,
		relative = "editor",
		height = input_height,
		col = (vim.o.columns - M.config.window.width) / 2,
		row = (vim.o.lines - total_height) / 2,
		border = "single",
		title = "输入区（按ESC关闭, Ctrl+Enter 提交）",
		title_pos = "center",
	})

	state.output_win = vim.api.nvim_open_win(state.output_buf, true, {
		relative = "editor",
		width = M.config.window.width,
		height = output_height,
		col = (vim.o.columns - M.config.window.width) / 2,
		row = (vim.o.lines - total_height) / 2 + input_height + 2,
		border = "single",
		title = "输出区",
		title_pos = "center",
	})

	vim.api.nvim_win_set_option(state.input_win, "winhl", "Normal:Normal,FloatBorder:FloatBorder")
	vim.api.nvim_win_set_option(state.output_win, "winhl", "Normal:Normal,FloatBorder:FloatBorder")
	vim.api.nvim_set_current_win(state.input_win)
	vim.cmd("startinsert!")

	M.setup_buffers()

	M.setup_autocmds()
end

function M.setup_buffers()
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

function M.setup_autocmds()
	vim.api.nvim_create_autocmd("BufWipeout", {
		buffer = state.input_buf,
		callback = function()
			if state.input_win and vim.api.nvim_win_is_valid(state.input_win) then
				vim.api.nvim_win_close(state.input_win, true)
			end
			if state.output_win and vim.api.nvim_win_is_valid(state.output_win) then
				vim.api.nvim_win_close(state.output_win, true)
			end
		end,
	})
end

function M.close_windows()
	vim.notify("正在关闭DeepSeek窗口...", vim.log.levels.INFO)
	local current_win = vim.api.nvim_get_current_win()
	if current_win == state.input_win or current_win == state.output_win then
		vim.cmd("wincmd p")
	end

	if state.input_win and vim.api.nvim_win_is_valid(state.input_win) then
		vim.api.nvim_win_close(state.input_win, true)
	end
	if state.output_win and vim.api.nvim_win_is_valid(state.output_win) then
		vim.api.nvim_win_close(state.output_win, true)
	end

	vim.defer_fn(function()
		if state.input_buf and vim.api.nvim_buf_is_valid(state.input_buf) then
			pcall(vim.api.nvim_buf_delete, state.input_buf, { force = true })
		end
		if state.output_buf and vim.api.nvim_buf_is_valid(state.output_buf) then
			pcall(vim.api.nvim_buf_delete, state.output_buf, { force = true })
		end

		state = {
			input_win = nil,
			output_win = nil,
			input_buf = nil,
			output_buf = nil,
		}
		vim.notify("DeepSeek窗口已关闭", vim.log.levels.INFO)
	end, 50)
end

function M.submit_input()
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
