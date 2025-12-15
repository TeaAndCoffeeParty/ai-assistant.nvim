-- lua/ai-assistant/context.lua

local M_context = {}
local P
local window_module

function M_context.setup(main_plugin, window_mod)
	P = main_plugin
	window_module = window_mod
end

--- 获取代码上下文信息
--- @param mode string 'current_line' | 'visual_selection' | 'file_full' | 'file_range' | 'folder_content'
--- @param start_line_arg string|nil (for folder path)
--- @param end_line_arg nil
--- @return table|nil {lines: table, filename: string, start_line: number, end_line: number, filetype: string}
local function get_code_context_info(mode, start_line_arg, end_line_arg)
	local buf = vim.api.nvim_get_current_buf()
	local filename = vim.api.nvim_buf_get_name(buf)
	local lines = {}
	local final_start_line, final_end_line

	if mode == "current_line" then
		local cursor_row, _ = unpack(vim.api.nvim_win_get_cursor(0))
		lines = vim.api.nvim_buf_get_lines(buf, cursor_row - 1, cursor_row, false)
		final_start_line = cursor_row
		final_end_line = cursor_row
	elseif mode == "visual_selection" then
		local srow, _ = unpack(vim.api.nvim_buf_get_mark(buf, "<"))
		local erow, _ = unpack(vim.api.nvim_buf_get_mark(buf, ">"))
		final_start_line = math.min(srow, erow)
		final_end_line = math.max(srow, erow)
		lines = vim.api.nvim_buf_get_lines(buf, final_start_line - 1, final_end_line, false)
	elseif mode == "file_full" then
		lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
		final_start_line = 1
		final_end_line = #lines

		if #lines > P.config.max_context_lines then
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
		local num_lines = vim.api.nvim_buf_line_count(buf)
		final_start_line = math.max(1, math.min(start_line_arg, num_lines))
		final_end_line = math.max(1, math.min(end_line_arg, num_lines))
		if final_start_line > final_end_line then
			final_start_line, final_end_line = final_end_line, final_start_line
		end
		lines = vim.api.nvim_buf_get_lines(buf, final_start_line - 1, final_end_line, false)
	elseif mode == "folder_content" then
		local folder_path = start_line_arg or "."
		local content = M_context.get_folder_h_cpp_content(folder_path)
		lines = vim.split(content, "\n")
		filename = folder_path .. "/ (all .h/.cpp files)"
		final_start_line = 1
		final_end_line = #lines
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

--- 获取文件夹内所有 .h 和 .cpp 文件的内容
--- @param folder_path string 要扫描的目录，默认为当前目录
--- @return string 返回拼接的所有文件内容
function M_context.get_folder_h_cpp_content(folder_path)
	folder_path = folder_path or "."

	local find_cmd = string.format(
		[[find "%s" -type f \( -name "*.h" -o -name "*.cpp" \)]],
		folder_path:gsub('"', '\\"') -- escape quotes
	)

	local handle = io.popen(find_cmd)
	if not handle then
		vim.notify("Failed to execute find command.", vim.log.levels.ERROR)
		return ""
	end

	local files = {}
	for file in handle:lines() do
		table.insert(files, file)
	end
	handle:close()

	local combined = ""
	for _, path in ipairs(files) do
		local f = io.open(path, "r")
		if f then
			local content = f:read("*a")
			f:close()
			combined = combined .. "\n\n// === File: " .. path .. " ===\n" .. content
		end
	end

	return combined
end

--- 通用聊天函数，带有代码上下文预填充
--- @param mode string 'current_line' | 'visual_selection' | 'file_full' | 'file_range' | 'folder_content'
--- @param start_line string|number|nil
--- @param end_line number|nil
function M_context.chat_with_context(mode, start_line, end_line)
	local context_info = get_code_context_info(mode, start_line, end_line)
	if not context_info then
		return
	end

	local filename_display = vim.fn.fnamemodify(context_info.filename, ":~:.")
	local formatted_context_str = string.format(
		"```%s\n%s\n```\n\nContext from '%s' lines %d-%d.\nMy question is:\n",
		context_info.filetype,
		table.concat(context_info.lines, "\n"),
		filename_display,
		context_info.start_line,
		context_info.end_line
	)

	P.open_chat_ui()

	vim.defer_fn(function()
		local state = window_module.get_state()
		if state and state.input_buf and vim.api.nvim_buf_is_valid(state.input_buf) then
			local lines_to_add = vim.split(formatted_context_str, "\n")
			vim.api.nvim_buf_set_lines(state.input_buf, 0, 0, false, lines_to_add)
			local cursor_line = #lines_to_add
			vim.api.nvim_win_set_cursor(state.input_win, { cursor_line, 0 })
			vim.cmd("startinsert!")
		end
	end, 100)
end

--- Calculates the approximate total tokens for a list of messages.
function M_context.calculate_total_tokens(messages, token_char_ratio)
	local total_char_count = 0
	token_char_ratio = token_char_ratio or 4

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
