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

	vim.api.nvim_win_set_option(state.input_win, "winhl", "Normal:Normal,FloatBorder:FloatBorder")
	vim.api.nvim_win_set_option(state.output_win, "winhl", "Normal:Normal,FloatBorder:FloatBorder")

	--	M.setup_buffers()
	setup_autocmds()

	--	vim.api.nvim_set_current_win(state.input_win)
	--	vim.cmd("startinsert!")
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
