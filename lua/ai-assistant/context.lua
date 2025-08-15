-- lua/ai-assistant/context.lua

local M_context = {} -- 这是这个新模块的公共接口
local P -- 用于引用主插件模块
local window_module -- 用于引用 window 模块

-- setup 函数将接收主插件模块 (main_plugin) 和 window 模块作为参数
function M_context.setup(main_plugin, window_mod)
	P = main_plugin -- 将主插件模块赋值给局部变量，方便内部函数使用
	window_module = window_mod -- 将 window 模块赋值给局部变量
end

--- 获取代码上下文信息
--- @param mode string 'current_line' | 'visual_selection' | 'file_full' | 'file_range'
--- @param start_line_arg number|nil (for 'file_range')
--- @param end_line_arg number|nil (for 'file_range')
--- @return table|nil {lines: table, filename: string, start_line: number, end_line: number, filetype: string}
local function get_code_context_info(mode, start_line_arg, end_line_arg)
	local buf = vim.api.nvim_get_current_buf()
	local filename = vim.api.nvim_buf_get_name(buf)
	local lines = {}
	local final_start_line, final_end_line

	if filename == "" or filename:match("^NvimTree_") then
		vim.notify("Cannot get context from unsaved buffer or special buffer.", vim.log.levels.WARN)
		return nil
	end

	if mode == "current_line" then
		local cursor_row, _ = unpack(vim.api.nvim_win_get_cursor(0))
		lines = vim.api.nvim_buf_get_lines(buf, cursor_row - 1, cursor_row, false)
		final_start_line = cursor_row
		final_end_line = cursor_row
	elseif mode == "visual_selection" then
		-- '< and '> marks are 1-based, inclusive
		local srow, _ = unpack(vim.api.nvim_buf_get_mark(buf, "<"))
		local erow, _ = unpack(vim.api.nvim_buf_get_mark(buf, ">"))

		-- Visual selection might be backward, ensure start is always less than or equal to end
		final_start_line = math.min(srow, erow)
		final_end_line = math.max(srow, erow)

		-- nvim_buf_get_lines is 0-based for start and exclusive for end
		lines = vim.api.nvim_buf_get_lines(buf, final_start_line - 1, final_end_line, false)
	elseif mode == "file_full" then
		lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
		final_start_line = 1
		final_end_line = #lines

		-- Implement simple truncation for very large files
		if #lines > P.config.max_context_lines then -- 访问主插件的配置
			local cursor_row, _ = unpack(vim.api.nvim_win_get_cursor(0))
			local half_max = math.floor(P.config.max_context_lines / 2)
			final_start_line = math.max(1, cursor_row - half_max)
			final_end_line = math.min(#lines, cursor_row + half_max)
			lines = vim.api.nvim_buf_get_lines(buf, final_start_line - 1, final_end_line, false)
			vim.notify(
				string.format(
					"File too large, truncating to lines %d-%d around cursor.",
					final_start_line,
					final_end_line
				),
				vim.log.levels.INFO
			)
		end
	elseif mode == "file_range" then
		assert(start_line_arg and end_line_arg, "start_line and end_line must be provided for 'file_range' mode")
		-- Ensure valid range, adjust for 0-based API, 1-based user input
		local num_lines = vim.api.nvim_buf_line_count(buf)
		final_start_line = math.max(1, math.min(start_line_arg, num_lines))
		final_end_line = math.max(1, math.min(end_line_arg, num_lines))
		if final_start_line > final_end_line then
			final_start_line, final_end_line = final_end_line, final_start_line
		end
		lines = vim.api.nvim_buf_get_lines(buf, final_start_line - 1, final_end_line, false)
	else
		vim.notify("Invalid context mode: " .. mode, vim.log.levels.ERROR)
		return nil
	end

	if #lines == 0 then
		vim.notify("No code context found for this mode.", vim.log.levels.WARN)
		return nil
	end

	return {
		lines = lines,
		filename = filename,
		start_line = final_start_line,
		end_line = final_end_line,
		filetype = vim.bo[buf].filetype or "plaintext",
	}
end
--- 通用聊天函数，带有代码上下文预填充
--- @param mode string 'current_line' | 'visual_selection' | 'file_full' | 'file_range'
--- @param start_line number|nil
--- @param end_line number|nil
function M_context.chat_with_context(mode, start_line, end_line)
	local context_info = get_code_context_info(mode, start_line, end_line)
	if not context_info then
		return
	end

	-- 构建要预填充到输入缓冲区的字符串
	local filename_display = vim.fn.fnamemodify(context_info.filename, ":~:.") -- 显示相对路径或文件名
	local formatted_context_str = string.format(
		"```%s\n%s\n```\n\nContext from '%s' lines %d-%d.\nMy question is:\n",
		context_info.filetype,
		table.concat(context_info.lines, "\n"),
		filename_display,
		context_info.start_line,
		context_info.end_line
	)

	P.open_chat_ui() -- 调用主插件的 UI 函数

	-- 使用 defer_fn 确保窗口已经创建
	vim.defer_fn(function()
		local state = window_module.get_state() -- 调用 window 模块的函数
		if state and state.input_buf and vim.api.nvim_buf_is_valid(state.input_buf) then
			local lines_to_add = vim.split(formatted_context_str, "\n")

			-- 在缓冲区头部插入新行，而不是替换整个缓冲区
			-- (0, 0) 表示在第0行（即第一行）之前插入
			vim.api.nvim_buf_set_lines(state.input_buf, 0, 0, false, lines_to_add)

			-- 将光标移动到 "My question is:" 之后
			-- 现在 "My question is:" 所在行是新插入内容中的最后一行
			local cursor_line = #lines_to_add -- 新插入内容的行数就是其最后一行
			vim.api.nvim_win_set_cursor(state.input_win, { cursor_line, 0 })
			vim.cmd("startinsert!") -- 自动进入插入模式
		end
	end, 100) -- 延迟100ms
end

--- Calculates the approximate total tokens for a list of messages.
--- This is a rough character-based estimate.
---
--- @param messages table A list of message tables, where each table has a 'content' field.
---                      Example: {{role = "system", content = "You are a helpful assistant."},
---                                {role = "user", content = "Hello!"},
---                                {role = "assistant", content = "Hi there!"}}
--- @param token_char_ratio number The approximate number of characters per token.
---                               (e.g., 4 for English, 2-3 for Chinese characters)
--- @return number The estimated total token count.
function M_context.calculate_total_tokens(messages, token_char_ratio)
	local total_char_count = 0
	token_char_ratio = token_char_ratio or 4 -- Fallback default if not provided

	if messages then
		for _, message in ipairs(messages) do
			if message.content and type(message.content) == "string" then
				total_char_count = total_char_count + #message.content
			end
		end
	end

	return math.ceil(total_char_count / token_char_ratio)
end

return M_context
