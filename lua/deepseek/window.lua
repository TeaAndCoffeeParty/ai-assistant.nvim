local M = {}

-- 保存窗口和缓冲区引用
local state = {
	input_win = nil,
	output_win = nil,
	input_buf = nil,
	output_buf = nil,
}

local function setup_autocmds()
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

local function setup_buffers()
	local input_buf = vim.bo[state.input_buf]
	local output_buf = vim.bo[state.output_buf]

	local input_win = vim.wo[state.input_win]
	local output_win = vim.wo[state.output_win]

	-- 输入缓冲区设置
	input_buf.buftype = ""
	input_buf.filetype = "markdown"
	input_buf.modifiable = true
	-- 输入窗口设置
	input_win.number = false
	input_win.relativenumber = false
	input_win.wrap = true
	input_win.winhighlight = "Normal:Normal,FloatBorder:FloatBorder"

	-- 输出缓冲区设置
	output_buf.buftype = "nofile"
	output_buf.filetype = "markdown"
	output_buf.modifiable = true
	-- 输出窗口设置
	output_win.number = false
	output_win.relativenumber = false
	output_win.wrap = true
	output_win.winhighlight = "Normal:Normal,FloatBorder:FloatBorder"

	-- 设置初始内容
	vim.api.nvim_buf_set_lines(state.input_buf, 0, -1, false, { "" })
	vim.api.nvim_buf_set_lines(state.output_buf, 0, -1, false, { "等待您的问题..." })

	output_buf.modifiable = false
	output_buf.readonly = true

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
		"q",
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

-- 打开聊天窗口
function M.create(config)
	-- 如果窗口已经存在，则聚焦到输入窗口
	if state.input_win and vim.api.nvim_win_is_valid(state.input_win) then
		vim.api.nvim_set_current_win(state.input_win)
		return
	end

	-- 创建两个缓冲区
	state.input_buf = vim.api.nvim_create_buf(false, true)
	state.output_buf = vim.api.nvim_create_buf(false, true)

	local total_height = config.height
	local input_height = math.floor(total_height * config.split_ratio)
	local output_height = total_height - input_height - 1

	state.output_win = vim.api.nvim_open_win(state.output_buf, true, {
		relative = "editor",
		width = config.width,
		height = output_height,
		col = (vim.o.columns - config.width) / 2,
		row = (vim.o.lines - total_height) / 2,
		border = "single",
		title = "输出区",
		title_pos = "center",
	})

	state.input_win = vim.api.nvim_open_win(state.input_buf, true, {
		width = config.width,
		relative = "editor",
		height = input_height,
		col = (vim.o.columns - config.width) / 2,
		row = (vim.o.lines - total_height) / 2 + output_height + 2,
		border = "single",
		title = "输入区（按ESC关闭, Ctrl+Enter 提交）",
		title_pos = "center",
	})

	setup_buffers()
	setup_autocmds()

	vim.api.nvim_set_current_win(state.input_win)
	vim.cmd("startinsert!")

	return state
end

function M.close()
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

function M.get_state()
	return state
end

return M
