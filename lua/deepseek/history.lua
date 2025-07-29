local M = { chat_history = {} }

local config = require("deepseek.config")

M.history_win_id = nil
M.history_buf_id = nil
-- 新增：发送给 AI 的上下文开始索引，默认为1（从头开始）
M.context_start_index = 1

-- 格式化历史记录为 markdown 行
-- messages_to_ai 仍然是实际即将发送的列表
-- current_context_start_idx 用于在显示时判断状态
local function format_history_lines(chat_history, messages_to_ai, current_context_start_idx)
	local lines = {}

	if #chat_history == 0 then
		table.insert(lines, "**--- Full Chat History ---**")
		table.insert(lines, "")
		table.insert(lines, "No History available yet.")
		table.insert(lines, "")
	else
		table.insert(lines, "**--- Full Chat History ---**")
		table.insert(lines, "")
		for i, item in ipairs(chat_history) do
			-- 添加一个标记，指示这部分是否在当前 AI 上下文范围内
			local context_marker = ""
			if i >= current_context_start_idx then
				context_marker = "(Context)"
			end

			table.insert(
				lines,
				string.format("--- **%s** (%s) %s---", item.role:upper(), item.time or "N/A", context_marker)
			)
			if item.content then
				local content_with_code_blocks = {}
				local in_code_block = false
				for _, l in ipairs(vim.split(item.content, "\n", { plain = true })) do
					if l:match("^```") then
						table.insert(content_with_code_blocks, l)
						in_code_block = not in_code_block
					else
						if in_code_block then
							table.insert(content_with_code_blocks, l)
						else
							table.insert(content_with_code_blocks, "  " .. l)
						end
					end
				end
				if in_code_block then
					table.insert(content_with_code_blocks, "```")
				end

				for _, l_formatted in ipairs(content_with_code_blocks) do
					table.insert(lines, l_formatted)
				end
			else
				table.insert(lines, "  (No content)")
			end
			table.insert(lines, string.rep("-", 40))
			table.insert(lines, "")
		end
	end

	table.insert(lines, string.rep("=", 40))
	if current_context_start_idx > #chat_history then
		-- 如果指针已经越过了当前历史的末尾，说明下一次交互是新会话
		table.insert(lines, "**--- Next AI interaction will start a NEW conversation! ---**")
		table.insert(lines, "  (Full chat history preserved, but context cleared for AI)")
	else
		table.insert(
			lines,
			string.format("**--- Messages to be sent to AI (Max %d) ---**", config.config.history.chat_max_count)
		)
	end

	table.insert(lines, "")

	if #messages_to_ai == 0 then
		if current_context_start_idx > #chat_history then
			table.insert(lines, "  Only your NEW message will be sent.")
		else
			table.insert(lines, "  No messages will be sent.")
		end
	else
		for i, msg in ipairs(messages_to_ai) do
			local role_prefix = (msg.role == "user" and "User: ") or "Assistant: "
			local content_preview = ""
			local max_count_per_line = 79

			if msg.content then
				local preview = msg.content:gsub("\n", " "):gsub("%s+", " ")
				if #preview > max_count_per_line then
					content_preview = preview:sub(1, max_count_per_line) .. "..."
				else
					content_preview = preview
				end
			end
			table.insert(lines, string.format("  %d. %s%s", i, role_prefix, content_preview))
		end
	end
	table.insert(lines, string.rep("=", 40))
	table.insert(lines, "")

	return lines
end

function M.insertHistory(role, content)
	local initial_history_len = #M.chat_history
	table.insert(M.chat_history, {
		role = role,
		content = content,
		time = os.date("%Y-%m-%d %H:%M:%S"),
	})

	-- 如果历史记录超过某个限制，移除最旧的
	if #M.chat_history > config.config.history.max_save_count then
		local removed_count = #M.chat_history - config.config.history.max_save_count
		for i = 1, removed_count do
			table.remove(M.chat_history, 1)
		end
		-- 调整 context_start_index，使其指向正确的相对位置
		-- 如果 context_start_index > 1，则它也需要向前移动被移除的数量
		M.context_start_index = math.max(1, M.context_start_index - removed_count)
	end

	-- 计算发送给 AI 的 messages 列表
	local messages = {}
	-- 实际发送给 AI 的起始索引：取 context_start_index 和 chat_max_count 限制中更靠后的那个
	local start_index_for_ai_prompt =
		math.max(M.context_start_index, #M.chat_history - config.config.history.chat_max_count + 1)

	for i = start_index_for_ai_prompt, #M.chat_history do
		table.insert(messages, {
			role = M.chat_history[i].role,
			content = M.chat_history[i].content,
		})
	end

	-- 如果历史窗口是打开的，就更新它
	if M.history_win_id and vim.api.nvim_win_is_valid(M.history_win_id) then
		-- 这里的 messages_for_display 和 messages 是一样的，因为都是实时计算
		local lines = format_history_lines(M.chat_history, messages, M.context_start_index)
		vim.api.nvim_buf_set_option(M.history_buf_id, "modifiable", true)
		vim.api.nvim_buf_set_lines(M.history_buf_id, 0, -1, false, lines)
		vim.api.nvim_buf_set_option(M.history_buf_id, "modifiable", false)

		-- 滚动到最新内容（可能是在消息队列的底部）
		local line_count = vim.api.nvim_buf_line_count(M.history_buf_id)
		vim.api.nvim_win_set_cursor(M.history_win_id, { line_count, 0 })
	end

	return messages
end

function M.clearHistory()
	M.chat_history = {}
	M.context_start_index = 1 -- 清空所有历史时，重置指针
	-- 如果历史窗口开着，也关掉
	if M.history_win_id and vim.api.nvim_win_is_valid(M.history_win_id) then
		vim.api.nvim_win_close(M.history_win_id, true)
		M.history_win_id = nil
		M.history_buf_id = nil
	end
	vim.notify("Full chat history is clear", vim.log.levels.INFO)
end

-- 新增函数：重置发送给 AI 的提示上下文
function M.resetPromptContext()
	-- 将指针设置到当前历史记录的下一个位置，使得下一次只发送新消息
	M.context_start_index = #M.chat_history + 1
	vim.notify("AI prompt context has been reset for the next interaction.", vim.log.levels.INFO)

	-- 如果历史窗口是打开的，就更新它以反映这个状态
	if M.history_win_id and vim.api.nvim_win_is_valid(M.history_win_id) then
		local messages_for_display = {} -- 当重置模式开启时，显示为0条消息
		local lines = format_history_lines(M.chat_history, messages_for_display, M.context_start_index)
		vim.api.nvim_buf_set_option(M.history_buf_id, "modifiable", true)
		vim.api.nvim_buf_set_lines(M.history_buf_id, 0, -1, false, lines)
		vim.api.nvim_buf_set_option(M.history_buf_id, "modifiable", false)

		-- 滚动到最新内容
		local line_count = vim.api.nvim_buf_line_count(M.history_buf_id)
		vim.api.nvim_win_set_cursor(M.history_win_id, { line_count, 0 })
	end
end

-- 创建并显示浮动窗口 (此函数不变)
local function create_history_window(lines)
	local max_width = 0
	for _, line in ipairs(lines) do
		max_width = math.max(max_width, vim.fn.strwidth(line))
	end

	local screen_height = vim.o.lines
	local screen_width = vim.o.columns
	local win_height = math.min(#lines + 2, math.floor(screen_height * 0.9))
	local win_width = math.min(max_width + 4, math.floor(screen_width * 0.4))
	local row = math.floor((screen_height - win_height) / 2)
	local col = math.floor((screen_width - win_width))

	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
	vim.api.nvim_buf_set_option(buf, "readonly", true)
	vim.api.nvim_buf_set_option(buf, "modifiable", false)
	vim.api.nvim_buf_set_option(buf, "filetype", "markdown")
	vim.api.nvim_buf_set_option(buf, "concealcursor", "n")
	vim.api.nvim_buf_set_option(buf, "conceallevel", 2)

	local opts = {
		relative = "editor",
		row = row,
		col = col,
		width = win_width,
		height = win_height,
		border = "rounded",
		focusable = true,
		style = "minimal",
	}
	local win_id = vim.api.nvim_open_win(buf, true, opts)

	-- 设置光标到底部，实现自动滚动到底部
	local line_count = vim.api.nvim_buf_line_count(buf)
	vim.api.nvim_win_set_cursor(win_id, { line_count, 0 })

	vim.keymap.set("n", "q", "<cmd>close<CR>", {
		buffer = buf,
		nowait = true,
		silent = true,
		desc = "Close Chat History Window",
	})
	return win_id, buf
end

function M.showHistory()
	-- 如果已经有历史窗口打开，先关闭它
	if M.history_win_id and vim.api.nvim_win_is_valid(M.history_win_id) then
		vim.api.nvim_win_close(M.history_win_id, true)
		M.history_win_id = nil
		M.history_buf_id = nil
	end

	-- 计算出即将发送给AI的messages列表（用于显示）
	local messages_to_ai = {}
	local start_index_for_ai_prompt =
		math.max(M.context_start_index, #M.chat_history - config.config.history.chat_max_count + 1)
	for i = start_index_for_ai_prompt, #M.chat_history do
		table.insert(messages_to_ai, {
			role = M.chat_history[i].role,
			content = M.chat_history[i].content,
		})
	end

	-- format_history_lines 传入两部分数据，以及当前的 context_start_index
	local lines = format_history_lines(M.chat_history, messages_to_ai, M.context_start_index)
	local win_id, buf = create_history_window(lines)

	M.history_win_id = win_id
	M.history_buf_id = buf
end

function M.save_history()
	local history_path = vim.fn.stdpath("data") .. "/ai_chat_history.json"
	local ok, err = pcall(function()
		-- 确保只保存聊天历史，不保存 context_start_index，因为它是一个运行时状态
		vim.fn.writefile({ vim.fn.json_encode(M.chat_history) }, history_path)
	end)
	if not ok then
		vim.notify("Save History to: " .. err, vim.log.levels.ERROR)
	else
		vim.notify("History saved to : " .. history_path, vim.log.levels.INFO)
	end
end

function M.load_history()
	local history_path = vim.fn.stdpath("data") .. "/ai_chat_history.json"
	if vim.fn.filereadable(history_path) == 1 then
		local ok, data = pcall(function()
			return vim.fn.json_decode(vim.fn.readfile(history_path))
		end)
		if ok and type(data) == "table" then
			M.chat_history = data
			M.context_start_index = 1 -- 加载历史后，默认从头开始上下文
			vim.notify("History has been loaded", vim.log.levels.INFO)
		else
			vim.notify("Load History failed or invalid content.", vim.log.levels.WARN)
			M.chat_history = {}
			M.context_start_index = 1
		end
	else
		vim.notify("No History file and new one created.", vim.log.levels.INFO)
		M.chat_history = {}
		M.context_start_index = 1
	end
end

return M
