local M = { chat_history = {} }

local config = require("deepseek.config")

M.history_win_id = nil
M.history_buf_id = nil
-- 新增：发送给 AI 的上下文开始索引，默认为1（从头开始）
M.context_start_index = 1

-- ======== Helper Functions (辅助函数) ========

--- 获取实际发送给 AI 的消息列表。
-- 根据 chat_history、context_start_index 和配置的 chat_max_count 计算。
-- @return table 格式化后的消息列表，每个元素包含 role 和 content。
local function get_messages_for_ai_prompt()
	local messages = {}
	-- 实际发送给 AI 的起始索引：取 context_start_index 和 chat_max_count 限制中更靠后的那个
	-- 确保不会因为 max_save_count 导致越界，所以也要和 chat_history 的实际长度关联
	local start_index_for_ai_prompt =
		math.max(M.context_start_index, #M.chat_history - config.config.history.chat_max_count + 1)

	-- 确保起始索引不小于1
	start_index_for_ai_prompt = math.max(1, start_index_for_ai_prompt)

	for i = start_index_for_ai_prompt, #M.chat_history do
		-- 确保消息内容存在，避免发送nil
		if M.chat_history[i] and M.chat_history[i].role and M.chat_history[i].content then
			table.insert(messages, {
				role = M.chat_history[i].role,
				content = M.chat_history[i].content,
			})
		end
	end
	return messages
end

--- 格式化历史记录为 markdown 行，用于显示在历史窗口中。
-- @param chat_history table 完整的聊天历史记录。
-- @param messages_for_display table 实际将发送给 AI 的消息列表（用于在显示中预览）。
-- @param current_context_start_idx number 当前 AI 上下文的起始索引。
-- @return table 包含所有格式化行的列表。
local function format_history_lines(chat_history, messages_for_display, current_context_start_idx)
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
					table.insert(content_with_code_blocks, "```") -- 如果代码块没有关闭，手动关闭
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

	if #messages_for_display == 0 then
		if current_context_start_idx > #chat_history then
			table.insert(lines, "  Only your NEW message will be sent.")
		else
			table.insert(lines, "  No messages will be sent.")
		end
	else
		for i, msg in ipairs(messages_for_display) do
			local role_prefix = (msg.role == "user" and "User: ") or "Assistant: "
			local content_preview = ""
			local max_count_per_line = 79

			if msg.content then
				local preview = msg.content:gsub("\n", " "):gsub("%s+", " ") -- 移除换行符和多余空格
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

--- 创建并显示浮动窗口。
-- @param lines table 要在窗口中显示的行。
-- @return number win_id 窗口ID。
-- @return number buf_id 缓冲区ID。
local function create_history_window(lines)
	local max_width = 0
	for _, line in ipairs(lines) do
		max_width = math.max(max_width, vim.fn.strwidth(line))
	end

	local screen_height = vim.o.lines
	local screen_width = vim.o.columns
	local win_height = math.min(#lines + 2, math.floor(screen_height * 0.9))
	local win_width = math.min(max_width + 4, math.floor(screen_width * 0.7)) -- 调整宽度使其更可见
	local row = math.floor((screen_height - win_height) / 2)
	local col = math.floor((screen_width - win_width) / 2) -- 居中显示

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

--- 更新历史记录浮动窗口的内容。
-- 此函数检查窗口是否打开且有效，然后格式化并更新其内容。
local function update_history_window_content()
	if M.history_win_id and vim.api.nvim_win_is_valid(M.history_win_id) then
		-- 确定要显示为 "即将发送给 AI" 的消息
		local messages_for_ai_display = {}
		-- 只有当 context_start_index 不完全重置时，才计算要发送给AI的消息
		if M.context_start_index <= #M.chat_history then
			messages_for_ai_display = get_messages_for_ai_prompt()
		end

		local lines = format_history_lines(M.chat_history, messages_for_ai_display, M.context_start_index)
		vim.api.nvim_buf_set_option(M.history_buf_id, "modifiable", true)
		vim.api.nvim_buf_set_lines(M.history_buf_id, 0, -1, false, lines)
		vim.api.nvim_buf_set_option(M.history_buf_id, "modifiable", false)

		-- 滚动到最新内容（可能是在消息队列的底部）
		local line_count = vim.api.nvim_buf_line_count(M.history_buf_id)
		vim.api.nvim_win_set_cursor(M.history_win_id, { line_count, 0 })
	end
end

-- ======== Public Functions (公共函数) ========

--- 向聊天历史中插入一条新消息。
-- 管理历史记录的长度限制，并根据当前上下文计算即将发送给 AI 的消息。
-- 如果历史窗口已打开，则更新其内容。
-- @param role string 消息的角色 ('user' 或 'assistant')。
-- @param content string 消息内容。
-- @return table 实际将发送给 AI 的消息列表。
function M.insertHistory(role, content)
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
	local messages = get_messages_for_ai_prompt()

	-- 如果历史窗口是打开的，就更新它
	update_history_window_content()

	return messages
end

--- 清除所有聊天历史记录。
-- 同时关闭历史窗口（如果已打开），并重置 AI 上下文指针。
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

--- 重置发送给 AI 的提示上下文。
-- 将上下文指针设置到当前历史记录的下一个位置，使得下一次只发送新消息。
-- 如果历史窗口是打开的，则更新其内容以反映此状态。
function M.resetPromptContext()
	-- 将指针设置到当前历史记录的下一个位置，使得下一次只发送新消息
	M.context_start_index = #M.chat_history + 1
	vim.notify("AI prompt context has been reset for the next interaction.", vim.log.levels.INFO)

	-- 如果历史窗口是打开的，就更新它以反映这个状态
	update_history_window_content()
end

--- 显示聊天历史记录的浮动窗口。
-- 如果窗口已打开，会先关闭再重新打开以刷新内容。
function M.showHistory()
	-- 如果已经有历史窗口打开，先关闭它
	if M.history_win_id and vim.api.nvim_win_is_valid(M.history_win_id) then
		vim.api.nvim_win_close(M.history_win_id, true)
		M.history_win_id = nil
		M.history_buf_id = nil
	end

	-- 格式化历史行
	-- 在这里，messages_for_display 直接通过 get_messages_for_ai_prompt 获取，因为是显示当前状态
	local messages_for_display = get_messages_for_ai_prompt()
	local lines = format_history_lines(M.chat_history, messages_for_display, M.context_start_index)
	local win_id, buf = create_history_window(lines)

	M.history_win_id = win_id
	M.history_buf_id = buf
end

--- 将聊天历史保存到文件。
-- 文件路径为 `vim.fn.stdpath("data") .. "/ai_chat_history.json"`。
function M.save_history()
	local history_path = vim.fn.stdpath("data") .. "/ai_chat_history.json"
	local ok, err = pcall(function()
		-- 确保只保存聊天历史，不保存 context_start_index，因为它是一个运行时状态
		vim.fn.writefile({ vim.fn.json_encode(M.chat_history) }, history_path)
	end)
	if not ok then
		vim.notify("Save History failed: " .. err, vim.log.levels.ERROR)
	else
		vim.notify("History saved to: " .. history_path, vim.log.levels.INFO)
	end
end

--- 从文件加载聊天历史。
-- 文件路径为 `vim.fn.stdpath("data") .. "/ai_chat_history.json"`。
-- 如果文件不存在或内容无效，则初始化为空历史。
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
			vim.notify("Load History failed or invalid content. Starting with an empty history.", vim.log.levels.WARN)
			M.chat_history = {}
			M.context_start_index = 1
		end
	else
		vim.notify("No history file found. Starting with a new empty history.", vim.log.levels.INFO)
		M.chat_history = {}
		M.context_start_index = 1
	end
end

return M
