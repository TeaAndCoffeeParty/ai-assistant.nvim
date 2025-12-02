local M = {}

-- 保存窗口和缓冲区引用
local state = {
	input_win = nil,
	output_win = nil,
	input_buf = nil,
	output_buf = nil,
	cached_content = nil,
	config = nil, -- 保存配置以便重绘时使用
	autocmd_group_id = nil, -- 用于管理自动命令的ID
	is_full_width = false, -- 新增：是否当前处于全宽模式 (95%)
}

local function setup_buffers()
	local input_buf_obj = vim.bo[state.input_buf]
	local output_buf_obj = vim.bo[state.output_buf]

	local input_win_obj = vim.wo[state.input_win]
	local output_win_obj = vim.wo[state.output_win]

	-- 输入缓冲区设置
	input_buf_obj.buftype = "nofile"
	input_buf_obj.filetype = "text"
	input_buf_obj.modifiable = true
	input_buf_obj.bufhidden = "wipe"
	vim.api.nvim_buf_set_option(state.input_buf, "spell", false) -- 确保作用于 input_buf

	-- 输入窗口设置
	input_win_obj.number = false
	input_win_obj.relativenumber = false
	input_win_obj.wrap = true
	input_win_obj.winhighlight = "Normal:Normal,FloatBorder:FloatBorder"

	-- 输出缓冲区设置
	output_buf_obj.buftype = "nofile"
	output_buf_obj.filetype = "markdown"
	output_buf_obj.modifiable = true
	output_buf_obj.bufhidden = "wipe"
	output_buf_obj.syntax = "off"
	vim.api.nvim_buf_set_option(state.output_buf, "spell", false) -- 确保作用于 output_buf

	-- 输出窗口设置
	output_win_obj.number = false
	output_win_obj.relativenumber = false
	output_win_obj.wrap = true
	output_win_obj.winhighlight = "Normal:Normal,FloatBorder:FloatBorder"

	-- 设置初始内容
	if state.cached_content then
		vim.api.nvim_buf_set_lines(state.input_buf, 0, -1, false, state.cached_content.input_buf)
		vim.api.nvim_buf_set_lines(state.output_buf, 0, -1, false, state.cached_content.output_buf)
	else
		vim.api.nvim_buf_set_lines(state.input_buf, 0, -1, false, { "" })
		vim.api.nvim_buf_set_lines(state.output_buf, 0, -1, false, { "Waiting for your question ...", "" })
	end
	output_buf_obj.modifiable = false
	output_buf_obj.readonly = true

	-- 输入窗口映射
	vim.api.nvim_buf_set_keymap(
		state.input_buf,
		"n",
		"<Esc>",
		"<cmd>lua require('ai-assistant').close_windows()<CR>",
		{ noremap = true, silent = true, nowait = true, desc = "Close Chat Window" }
	)
	vim.api.nvim_buf_set_keymap(
		state.input_buf,
		"n",
		"q",
		"<cmd>lua require('ai-assistant').close_windows()<CR>",
		{ noremap = true, silent = true, nowait = true, desc = "Close Chat Window" }
	)
	vim.api.nvim_buf_set_keymap(
		state.input_buf,
		"n",
		"<leader>ds",
		"<cmd>lua require('ai-assistant').submit_input()<CR>",
		{ noremap = true, silent = true, nowait = true, desc = "Submit Input" }
	)
	vim.api.nvim_buf_set_keymap(
		state.input_buf,
		"i",
		"<CR>",
		"<cmd>lua require('ai-assistant').submit_input()<CR>",
		{ noremap = true, silent = true, nowait = true, desc = "Submit Input" }
	)
	vim.api.nvim_buf_set_keymap(
		state.input_buf,
		"i",
		"<S-CR>",
		"<CR>", -- Shift+Enter to insert a literal newline
		{ noremap = true, silent = true, nowait = true, desc = "插入新行" }
	)
	vim.api.nvim_buf_set_keymap(
		state.input_buf,
		"i",
		"<C-j>",
		"<CR>",
		{ noremap = true, silent = true, nowait = true, desc = "插入新行 (Ctrl+J)" }
	)

	-- 输出窗口映射
	vim.api.nvim_buf_set_keymap(
		state.output_buf,
		"n",
		"<Esc>",
		"<cmd>lua require('ai-assistant').close_windows()<CR>", -- 关闭窗口
		{ noremap = true, silent = true, nowait = true, desc = "Close Chat Window" }
	)
	vim.api.nvim_buf_set_keymap(
		state.output_buf,
		"n",
		"q",
		"<cmd>lua require('ai-assistant').close_windows()<CR>", -- 关闭窗口
		{ noremap = true, silent = true, nowait = true, desc = "Close Chat Window" }
	)
	vim.api.nvim_buf_set_keymap(
		state.output_buf,
		"n",
		"i",
		"<cmd>lua vim.api.nvim_set_current_win(" .. state.input_win .. ")<CR>", -- 切换到输入窗口
		{ noremap = true, silent = true, nowait = true, desc = "Switch to Input Window" }
	)
	vim.api.nvim_buf_set_keymap(
		state.output_buf,
		"n",
		"<CR>",
		"<cmd>lua vim.api.nvim_set_current_win(" .. state.input_win .. ")<CR>", -- 按回车也切换到输入窗口，方便操作
		{ noremap = true, silent = true, nowait = true, desc = "Switch to Input Window" }
	)
end

-- 负责设置所有自动命令，包括 FileType 和 VimResized
local function setup_autocmds_for_windows()
	-- 清除旧的 Autocmd Group，确保每次只注册一次
	if state.autocmd_group_id then
		vim.api.nvim_del_augroup_by_id(state.autocmd_group_id)
		state.autocmd_group_id = nil
	end

	state.autocmd_group_id = vim.api.nvim_create_augroup("AIAssistantWinGroup", { clear = true })

	-- FileType 自动命令
	vim.api.nvim_create_autocmd("FileType", {
		group = state.autocmd_group_id,
		pattern = { "markdown", "text" },
		callback = function()
			if vim.api.nvim_get_current_buf() == state.output_buf then
				vim.opt_local.spell = false
			end
		end,
		desc = "Disable spell for AI Assistant output buffer",
	})

	-- VimResized 自动命令
	vim.api.nvim_create_autocmd("VimResized", {
		group = state.autocmd_group_id,
		callback = function()
			M.resize_windows() -- 调用重绘函数
		end,
		desc = "Resize AI Assistant windows on VimResized",
	})
end

-- 新增函数：根据当前屏幕尺寸和配置重新调整窗口大小
function M.resize_windows()
	if
		not state.input_win
		or not vim.api.nvim_win_is_valid(state.input_win)
		or not state.output_win
		or not vim.api.nvim_win_is_valid(state.output_win)
		or not state.config
	then
		return -- 窗口未打开或配置不存在，无需重绘
	end

	local config = state.config
	local screen_width = vim.o.columns
	local screen_height = vim.o.lines

	local actual_width
	if state.is_full_width then
		actual_width = math.floor(screen_width * 0.95) -- 95% 宽度
	else
		actual_width = math.floor(screen_width * config.width) -- 原始配置宽度
	end

	local total_actual_height = math.floor(screen_height * config.height)

	-- 应用最小尺寸限制
	if total_actual_height < 10 then
		total_actual_height = 10
	end
	if actual_width < 40 then
		actual_width = 40
	end

	local input_actual_height = math.floor(total_actual_height * config.split_ratio)
	local output_actual_height = total_actual_height - input_actual_height - 1 -- 减去边框和分隔行

	-- 确保输入输出窗口至少有最小高度
	if input_actual_height < 3 then
		input_actual_height = 3
	end
	if output_actual_height < 3 then
		output_actual_height = 3
	end

	-- 重新计算 total_actual_height 以适应调整后的 input/output_actual_height
	total_actual_height = input_actual_height + output_actual_height + 2

	-- 窗口居中靠右计算 (保持你原有的逻辑)
	local col_start = math.floor((screen_width - actual_width))
	local row_start = math.floor((screen_height - total_actual_height) / 2)

	-- 获取当前窗口配置，然后更新尺寸和位置，以保留其他如 border, title 等设置
	local output_win_cfg = vim.api.nvim_win_get_config(state.output_win)
	local input_win_cfg = vim.api.nvim_win_get_config(state.input_win)

	output_win_cfg.width = actual_width
	output_win_cfg.height = output_actual_height
	output_win_cfg.col = col_start
	output_win_cfg.row = row_start

	input_win_cfg.width = actual_width
	input_win_cfg.height = input_actual_height
	input_win_cfg.col = col_start
	input_win_cfg.row = row_start + output_actual_height + 2

	vim.api.nvim_win_set_config(state.output_win, output_win_cfg)
	vim.api.nvim_win_set_config(state.input_win, input_win_cfg)

	-- 重新设置光标位置
	local line_count = vim.api.nvim_buf_line_count(state.output_buf)
	vim.api.nvim_win_set_cursor(state.output_win, { line_count, 0 })
	vim.api.nvim_set_current_win(state.input_win)
	vim.cmd("startinsert!") -- 重新进入插入模式
end

-- 新增函数：切换窗口宽度模式
function M.toggle_width()
	if not state.input_win or not vim.api.nvim_win_is_valid(state.input_win) then
		vim.notify("AI Assistant window is not open.", vim.log.levels.WARN)
		return
	end

	state.is_full_width = not state.is_full_width -- 切换状态
	M.resize_windows() -- 触发重绘

	local width_desc = state.is_full_width and "95%" or "configured (" .. (state.config.width * 100) .. "%)"
	vim.notify("AI Assistant width toggled to " .. width_desc, vim.log.levels.INFO)
end

-- 打开聊天窗口
function M.create(config)
	-- 如果窗口已经存在，则聚焦到输入窗口
	if state.input_win and vim.api.nvim_win_is_valid(state.input_win) then
		M.close() -- 先关闭再重新创建，或者直接聚焦
		return
	end

	state.config = config -- 保存配置
	state.is_full_width = false -- 默认以配置宽度打开

	-- 创建两个缓冲区
	if not state.output_buf or not vim.api.nvim_buf_is_valid(state.output_buf) then
		state.output_buf = vim.api.nvim_create_buf(false, true)
	end
	if not state.input_buf or not vim.api.nvim_buf_is_valid(state.input_buf) then
		state.input_buf = vim.api.nvim_create_buf(false, true)
	end

	-- 初次创建时，根据 is_full_width 决定宽度
	local screen_width = vim.o.columns
	local screen_height = vim.o.lines

	local actual_width_on_create
	if state.is_full_width then
		actual_width_on_create = math.floor(screen_width * 0.95)
	else
		actual_width_on_create = math.floor(screen_width * config.width)
	end

	local total_actual_height = math.floor(screen_height * config.height)

	if total_actual_height < 10 then
		total_actual_height = 10
	end
	if actual_width_on_create < 40 then
		actual_width_on_create = 40
	end

	local input_actual_height = math.floor(total_actual_height * config.split_ratio)
	local output_actual_height = total_actual_height - input_actual_height - 1 -- 减去边框和分隔行

	-- 确保输入输出窗口至少有最小高度
	if input_actual_height < 3 then
		input_actual_height = 3
	end
	if output_actual_height < 3 then
		output_actual_height = 3
	end

	-- 重新计算 total_actual_height 以适应调整后的 input/output_actual_height
	total_actual_height = input_actual_height + output_actual_height + 2

	-- 窗口居中靠右计算
	local col_start = math.floor((screen_width - actual_width_on_create))
	local row_start = math.floor((screen_height - total_actual_height) / 2)

	state.output_win = vim.api.nvim_open_win(state.output_buf, true, {
		relative = "editor",
		width = actual_width_on_create, -- 使用计算出的宽度
		height = output_actual_height,
		col = col_start,
		row = row_start,
		border = "single",
		title = "Output Window (ESC to close, Enter/i to Input Window)",
		title_pos = "center",
	})

	state.input_win = vim.api.nvim_open_win(state.input_buf, true, {
		relative = "editor",
		width = actual_width_on_create, -- 使用计算出的宽度
		height = input_actual_height,
		col = col_start,
		row = row_start + output_actual_height + 2,
		border = "single",
		title = "Input Window（ESC to close, Enter to Submit, Shift+Enter/Ctrl+J to New Line）",
		title_pos = "center",
	})

	setup_buffers()
	setup_autocmds_for_windows() -- 调用新的 autocmd 设置函数

	-- 滚动到最底部
	local line_count = vim.api.nvim_buf_line_count(state.output_buf)
	vim.api.nvim_win_set_cursor(state.output_win, { line_count, 0 })

	vim.api.nvim_set_current_win(state.input_win)
	vim.cmd("startinsert!")

	return state
end

function M.close()
	vim.notify("Closing Chat Window ...", vim.log.levels.INFO)
	local current_win = vim.api.nvim_get_current_win()
	if current_win == state.input_win or current_win == state.output_win then
		vim.cmd("wincmd p") -- 切换到其他窗口
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
	state.config = nil -- 清除配置
	state.is_full_width = false -- 关闭时重置为默认值

	-- 清理自动命令
	if state.autocmd_group_id then
		vim.api.nvim_del_augroup_by_id(state.autocmd_group_id)
		state.autocmd_group_id = nil
	end

	vim.notify("Chat Window closed", vim.log.levels.INFO)
end

function M.get_state()
	return state
end

--- 获取用户输入，并尝试解析代码上下文
--- @return table|nil {raw_input_lines: table, full_prompt: string, code_context: string, user_question: string}
function M.get_input()
	local current_state = M.get_state()
	if not current_state or not current_state.input_buf then
		return nil
	end

	local raw_input_lines = vim.api.nvim_buf_get_lines(current_state.input_buf, 0, -1, false)
	local code_context_lines = {}
	local user_question_lines = {}
	local in_code_block = false
	local has_code_block_marker = false
	local has_question_marker = false
	local code_block_filetype = "plaintext" -- Default if not specified

	-- Try to parse the input buffer
	for i, line in ipairs(raw_input_lines) do
		if line:match("^```(%S*)$") then -- Matches ``` followed by optional filetype
			in_code_block = not in_code_block
			has_code_block_marker = true
			if in_code_block then -- Entering a code block
				local ft = line:match("^```(%S*)$")
				if ft and #ft > 0 then
					code_block_filetype = ft
				end
			end
		elseif not in_code_block and line:match("^My question is:$") then
			has_question_marker = true
			-- The actual user question starts from the next line
		elseif in_code_block then
			table.insert(code_context_lines, line)
		elseif has_question_marker then
			table.insert(user_question_lines, line)
		else
			-- If no code block or question marker, assume it's all user question
			-- This branch only hit if no special markers are found at all
			if not has_code_block_marker and not has_question_marker then
				table.insert(user_question_lines, line)
			end
		end
	end

	local code_context_str = ""
	if #code_context_lines > 0 then
		-- Reconstruct the code block exactly as it was provided for the AI
		code_context_str =
			string.format("```%s\n%s\n```\n", code_block_filetype, table.concat(code_context_lines, "\n"))
	end

	local user_question_str = table.concat(user_question_lines, "\n")

	-- If no specific question marker was found, treat the whole input as the question
	if not has_question_marker and not has_code_block_marker then
		user_question_str = table.concat(raw_input_lines, "\n")
		code_context_str = "" -- No distinct code context
	end

	-- Construct the full prompt that will be sent to the AI
	local full_prompt = ""
	if code_context_str ~= "" then
		full_prompt = full_prompt .. "Here is some code context:\n" .. code_context_str .. "\n"
	end
	full_prompt = full_prompt .. "My question is: " .. user_question_str

	if #vim.trim(user_question_str) == 0 and #vim.trim(code_context_str) == 0 then
		vim.notify("Empty input.", vim.log.levels.WARN)
		return nil
	end

	return {
		raw_input_lines = raw_input_lines, -- 用户在输入缓冲区中输入的原始行
		full_prompt = full_prompt, -- 发送给 AI 的最终提示
		code_context = code_context_str, -- 解析出的代码部分
		user_question = user_question_str, -- 解析出的用户纯文本问题
	}
end

function M.echo_user_input(input)
	vim.bo[state.output_buf].filetype = "text"
	local display_lines = {}
	for _, line in ipairs(input) do
		if line ~= "" then
			table.insert(display_lines, "> " .. line)
		end
	end

	M.safe_buf_update(table.concat(display_lines, "\n\n"))
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
