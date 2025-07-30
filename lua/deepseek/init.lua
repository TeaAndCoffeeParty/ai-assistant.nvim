local M = {}

local window = require("deepseek.window")
local config = require("deepseek.config")
local history = require("deepseek.history")
local request_api = require("deepseek.api")

function M.setup(opts)
	-- 合并默认配置和用户配置
	M.config = config.setup(opts)

	-- 如果插件被禁用则返回
	if not M.config.enabled then
		vim.notify("AI Chat Plugin Disabled")
		return
	end

	local model_config, err = config.get_model()

	if err or not model_config then
		error("Get Model Config Failed: " .. (err or "Unkown Error"))
	end

	-- 关键配置验证
	assert(
		type(model_config.api_key) == "string" and #model_config.api_key > 0,
		"Pleae Config AI Chat API Key(setup() or get environment API KEY)"
	)
	assert(model_config.api_url, "Please Config api_url")
	assert(model_config.model, "Please Config model")

	-- 设置快捷键,命令
	M.setup_commands()

	history.load_history()

	-- 在这里添加你的插件逻辑
	vim.notify(model_config.model .. " has benn loaded!")
end

-- 设置快捷键函数
function M.setup_commands()
	vim.api.nvim_create_user_command("ChatClearHistory", function()
		history.clearHistory()
		vim.notify("AI Chat history cleared")
	end, { desc = "Clear AI Chat History" })

	vim.api.nvim_create_user_command("ChatClearPrompt", function()
		history.resetPromptContext()
		vim.notify("AI Chat prompt context cleared")
	end, { desc = "Clear AI Chat Prompt Context" })
	vim.api.nvim_create_user_command("ChatShowHistory", function()
		history.showHistory()
	end, { desc = "Show AI Chat History" })

	vim.api.nvim_create_user_command("Chat", function()
		M.open_chat_ui()
	end, { desc = "Show AI Chat Window" })

	-- 新增命令: 引用当前行
	vim.api.nvim_create_user_command("ChatCurrentLine", function()
		M.chat_with_context("current_line")
	end, { desc = "Send Current Line to AI Chat" })

	-- 新增命令: 引用整个文件
	vim.api.nvim_create_user_command("ChatFile", function()
		M.chat_with_context("file_full")
	end, { desc = "Send Entire File to AI Chat" })

	-- 新增命令: 引用指定行范围
	-- :ChatRange <start_line> <end_line>
	vim.api.nvim_create_user_command("ChatRange", function(opts)
		local start_line = tonumber(opts.fargs[1])
		local end_line = tonumber(opts.fargs[2])
		if not start_line or not end_line or start_line <= 0 or end_line <= 0 or start_line > end_line then
			vim.notify("Usage: :ChatRange <start_line> <end_line>", vim.log.levels.ERROR)
			return
		end
		M.chat_with_context("file_range", start_line, end_line)
	end, { nargs = "*", desc = "Send File Range to AI Chat" })

	-- 统一 ChatVisual 命令，调用 M.chat_with_context
	vim.api.nvim_create_user_command("ChatVisual", function()
		M.chat_with_context("visual_selection")
	end, { range = true, desc = "Send Visual Selection to AI Chat" })

	vim.keymap.set("n", M.config.keymaps.open_chat, function()
		M.open_chat_ui()
	end, { desc = "Open AI Chat Window" })

	vim.keymap.set("v", M.config.keymaps.open_chat, ":ChatVisual<CR>", { desc = "Send Selected Content to Chat" })

	vim.keymap.set(
		"n",
		M.config.keymaps.chat_current_line,
		":ChatCurrentLine<CR>",
		{ desc = "Send Current Line to Chat" }
	)
	vim.keymap.set("n", M.config.keymaps.chat_file, ":ChatFile<CR>", { desc = "Send Entire File to Chat" })

	vim.keymap.set("n", M.config.keymaps.show_history, ":ChatShowHistory<CR>", { desc = "Show Chat History" })
	vim.keymap.set("n", M.config.keymaps.clear_history, ":ChatClearHistory<CR>", { desc = "Clear Chat History" })
	vim.keymap.set("n", M.config.keymaps.clear_prompt, ":ChatClearPrompt<CR>", { desc = "Clear Chat Prompt History" })

	local ai_chat_augroup = vim.api.nvim_create_augroup("AiChatHistory", { clear = true })
	vim.api.nvim_create_autocmd("VimLeavePre", {
		group = ai_chat_augroup,
		pattern = "*",
		callback = function()
			if history and type(history.save_history) == "function" then
				history.save_history()
			end
		end,
		desc = "Save AI chat history on Neovim exit",
	})
end

-- 打开聊天窗口
function M.open_chat_ui()
	window.create(M.config.window)
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
		if #lines > M.config.max_context_lines then
			local cursor_row, _ = unpack(vim.api.nvim_win_get_cursor(0))
			local half_max = math.floor(M.config.max_context_lines / 2)
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
function M.chat_with_context(mode, start_line, end_line)
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

	M.open_chat_ui() -- 打开聊天窗口

	-- 使用 defer_fn 确保窗口已经创建
	vim.defer_fn(function()
		local state = window.get_state()
		if state and state.input_buf then
			local lines_to_set = vim.split(formatted_context_str, "\n")
			vim.api.nvim_buf_set_lines(state.input_buf, 0, -1, false, lines_to_set)

			-- 将光标移动到 "My question is:" 之后，方便用户输入
			vim.api.nvim_win_set_cursor(state.input_win, { #lines_to_set, 0 })
			vim.cmd("startinsert!") -- 自动进入插入模式
		end
	end, 100) -- 延迟100ms
end

function M.close_windows()
	window.close()
end

function M.submit_input()
	local state = window.get_state()
	local input_data = window.get_input()
	if not input_data or not input_data.full_prompt then
		vim.notify("No input to submit.", vim.log.levels.WARN)
		return
	end

	window.echo_user_input(input_data.raw_input_lines)

	local full_response = ""
	local messages = history.insertHistory("user", input_data.full_prompt)
	vim.notify("Querying AI...", vim.log.levels.INFO, { title = "AI Chat" })

	request_api.query_stream(messages, {
		on_data = function(content)
			if content then
				full_response = full_response .. content
				window.safe_buf_update(content)
			end
		end,
		on_finish = function()
			history.insertHistory("assistant", full_response)

			window.safe_buf_update("\n\nTimestamp:" .. os.date("%Y-%m-%d %H:%M:%S"))
			window.safe_buf_update("\n\n-------------------\n")
			--清空输入区
			vim.api.nvim_buf_set_lines(state.input_buf, 0, -1, false, { "" })
			vim.api.nvim_win_set_cursor(state.input_win, { 1, 0 })
			vim.cmd("startinsert!")
			vim.bo[state.output_buf].filetype = "markdown"
		end,
		on_error = function(err)
			window.safe_buf_update("\n\n[ERROR] " .. tostring(err))
			window.safe_buf_update("\nTimestamp:" .. os.date("%Y-%m-%d %H:%M:%S"))
			window.safe_buf_update("\n\n-------------------\n")
			vim.api.nvim_buf_set_lines(state.input_buf, 0, -1, false, { "" })
			vim.bo[state.output_buf].filetype = "markdown"
			vim.notify("AI query failed: " .. tostring(err), vim.log.levels.ERROR, { title = "AI Chat Error" })
		end,
	})
end

return M
