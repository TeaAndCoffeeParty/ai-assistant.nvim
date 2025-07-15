local M = {}

-- 保存窗口和缓冲区引用
local state = {
	input_win = nil,
	output_win = nil,
	input_buf = nil,
	output_buf = nil,
	cached_content = nil,
}

local function setup_buffers()
	local input_buf = vim.bo[state.input_buf]
	local output_buf = vim.bo[state.output_buf]

	local input_win = vim.wo[state.input_win]
	local output_win = vim.wo[state.output_win]

	-- 输入缓冲区设置
	input_buf.buftype = "nofile"
	input_buf.filetype = "text"
	input_buf.modifiable = true
	input_buf.bufhidden = "wipe"
	vim.opt_local.spell = false

	-- 输入窗口设置
	input_win.number = false
	input_win.relativenumber = false
	input_win.wrap = true
	input_win.winhighlight = "Normal:Normal,FloatBorder:FloatBorder"

	-- 输出缓冲区设置
	output_buf.buftype = "nofile"
	output_buf.filetype = "markdown"
	output_buf.modifiable = true
	output_buf.bufhidden = "wipe"
	output_buf.syntax = "off"
	vim.api.nvim_buf_set_option(state.input_buf, "spell", false)

	-- 输出窗口设置
	output_win.number = false
	output_win.relativenumber = false
	output_win.wrap = true
	output_win.winhighlight = "Normal:Normal,FloatBorder:FloatBorder"

	-- 设置初始内容
	if state.cached_content then
		vim.api.nvim_buf_set_lines(state.input_buf, 0, -1, false, state.cached_content.input_buf)
		vim.api.nvim_buf_set_lines(state.output_buf, 0, -1, false, state.cached_content.output_buf)
	else
		vim.api.nvim_buf_set_lines(state.input_buf, 0, -1, false, { "" })
		vim.api.nvim_buf_set_lines(state.output_buf, 0, -1, false, { "等待您的问题...", "" })
	end
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
	vim.api.nvim_buf_set_keymap(
		state.input_buf,
		"i",
		"<CR>",
		"<cmd>lua require('deepseek').submit_input()<CR>",
		{ noremap = true, silent = true, nowait = true, desc = "提交输入" }
	)
	vim.api.nvim_buf_set_keymap(
		state.input_buf,
		"i",
		"<S-CR>",
		"<CR>",
		{ noremap = true, silent = true, nowait = true, desc = "插入新行" }
	)
end

local function setup_autocmd()
	vim.api.nvim_create_autocmd("FileType", {
		pattern = { "markdown", "text" },
		callback = function()
			if vim.api.nvim_get_current_buf() == state.output_buf then
				vim.opt_local.spell = false
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
	if not state.output_buf or not vim.api.nvim_buf_is_valid(state.output_buf) then
		state.output_buf = vim.api.nvim_create_buf(false, true)
	end
	if not state.input_buf or not vim.api.nvim_buf_is_valid(state.input_buf) then
		state.input_buf = vim.api.nvim_create_buf(false, true)
	end

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
		title = "输入区（按ESC关闭, Enter 提交,Ctrl+J换行）",
		title_pos = "center",
	})

	setup_buffers()
	setup_autocmd()

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

	if state.input_buf and vim.api.nvim_buf_is_valid(state.input_buf) then
		state.cached_content = {
			input_buf = vim.api.nvim_buf_get_lines(state.input_buf, 0, -1, false),
			output_buf = state.output_buf
					and vim.api.nvim_buf_is_valid(state.output_buf)
					and vim.api.nvim_buf_get_lines(state.output_buf, 0, -1, false)
				or {},
		}
	end

	if state.input_win and vim.api.nvim_win_is_valid(state.input_win) then
		vim.api.nvim_win_close(state.input_win, true)
	end
	if state.output_win and vim.api.nvim_win_is_valid(state.output_win) then
		vim.api.nvim_win_close(state.output_win, true)
	end

	state.input_win = nil
	state.output_win = nil

	vim.notify("DeepSeek窗口已关闭", vim.log.levels.INFO)
end

function M.get_state()
	return state
end

function M.get_input()
	local input_lines = vim.api.nvim_buf_get_lines(state.input_buf, 0, -1, false)
	local has_content = false
	for _, line in ipairs(input_lines) do
		if line:match("%S") then
			has_content = true
			break
		end
	end

	if not has_content then
		vim.notify("请输入有效内容", vim.log.levels.WARN)
		return nil
	end

	local prompt = table.concat(input_lines, "\n")

	local display_lines = {}
	for _, line in ipairs(input_lines) do
		if line ~= "" then
			table.insert(display_lines, "> " .. line)
		end
	end

	return {
		prompt = prompt,
		display_lines = display_lines,
	}
end

function M.echo_user_input(input)
	vim.bo[state.output_buf].filetype = "text"

	M.safe_buf_update(table.concat(input, "\n\n"))
	M.safe_buf_update("\n-------------------\n")
end

function M.safe_buf_update(content)
	if not (vim.api.nvim_win_is_valid(state.output_win) and vim.api.nvim_buf_is_valid(state.output_buf)) then
		return
	end

	local output_buf = vim.bo[state.output_buf]
	local current_lines = vim.api.nvim_buf_get_lines(state.output_buf, 0, -1, false)

	-- 如果 lines 是字符串，先转换成 table
	if type(content) == "string" then
		content = { content }
	end

	-- 启用修改
	output_buf.modifiable = true
	output_buf.readonly = false

	-- 如果缓冲区为空，直接添加所有行
	if #current_lines == 0 then
		vim.api.nvim_buf_set_lines(state.output_buf, 0, -1, false, content)
	else
		-- 获取最后一行
		local last_line = current_lines[#current_lines] or ""

		-- 处理新内容
		for _, line in ipairs(content) do
			-- 如果有换行符，则分割处理
			if line:find("\n") then
				local split_lines = vim.split(line, "\n")

				-- 第一部分追加到最后一行
				if split_lines[1] ~= "" then
					last_line = last_line .. split_lines[1]
					current_lines[#current_lines] = last_line
				end

				-- 剩余部分作为新行
				for i = 2, #split_lines do
					table.insert(current_lines, split_lines[i])
					last_line = split_lines[i]
				end
			else
				-- 没有换行符，直接追加到最后一行
				last_line = last_line .. line
				current_lines[#current_lines] = last_line
			end
		end

		-- 更新整个缓冲区
		vim.api.nvim_buf_set_lines(state.output_buf, 0, -1, false, current_lines)
	end

	-- 禁用修改
	output_buf.modifiable = false
	output_buf.readonly = true

	-- 滚动到最底部
	local line_count = vim.api.nvim_buf_line_count(state.output_buf)
	vim.api.nvim_win_set_cursor(state.output_win, { line_count, 0 })
end

return M
