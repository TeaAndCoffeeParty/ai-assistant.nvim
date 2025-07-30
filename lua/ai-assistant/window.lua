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
	local input_buf_obj = vim.bo[state.input_buf]
	local output_buf_obj = vim.bo[state.output_buf]

	local input_win_obj = vim.wo[state.input_win]
	local output_win_obj = vim.wo[state.output_win]

	-- 输入缓冲区设置
	input_buf_obj.buftype = "nofile"
	input_buf_obj.filetype = "text"
	input_buf_obj.modifiable = true
	input_buf_obj.bufhidden = "wipe"
	vim.opt_local.spell = false

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
	vim.api.nvim_buf_set_option(state.input_buf, "spell", false)

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

	local screen_width = vim.o.columns
	local screen_height = vim.o.lines

	local actual_width = math.floor(screen_width * config.width)
	local total_actual_height = math.floor(screen_height * config.height)

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
	end -- 至少3行高
	if output_actual_height < 3 then
		output_actual_height = 3
	end -- 至少3行高

	-- 重新计算 total_actual_height 以适应调整后的 input/output_actual_height
	total_actual_height = input_actual_height + output_actual_height + 2

	-- 窗口居中靠右计算
	local col_start = math.floor((screen_width - actual_width))
	local row_start = math.floor((screen_height - total_actual_height) / 2)

	state.output_win = vim.api.nvim_open_win(state.output_buf, true, {
		relative = "editor",
		width = actual_width,
		height = output_actual_height,
		col = col_start,
		row = row_start,
		border = "single",
		title = "Output Window",
		title_pos = "center",
	})

	state.input_win = vim.api.nvim_open_win(state.input_buf, true, {
		relative = "editor",
		width = actual_width,
		height = input_actual_height,
		col = col_start,
		row = row_start + output_actual_height + 2,
		border = "single",
		title = "Input Window（ESC to close, Enter to Submit, Ctrl+J to New Line）",
		title_pos = "center",
	})

	setup_buffers()
	setup_autocmd()

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
