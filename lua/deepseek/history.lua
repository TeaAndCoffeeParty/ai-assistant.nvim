local M = { chat_history = {} }

local config = require("deepseek.config")

M.history_win_id = nil
M.history_buf_id = nil

-- 格式化历史记录为 markdown 行
local function format_history_lines(chat_history, messages_to_ai)
	local lines = {}

	if #chat_history == 0 then
		table.insert(lines, "**--- Full Chat History ---**")
		table.insert(lines, "")
		table.insert(lines, "No History available yet.")
		table.insert(lines, "")
	else
		table.insert(lines, "**--- Full Chat History ---**")
		table.insert(lines, "")
		for _, item in ipairs(chat_history) do
			table.insert(lines, string.format("--- **%s** (%s) ---", item.role:upper(), item.time or "N/A"))
			if item.content then
				-- 检测并包裹代码块
				local content_with_code_blocks = {}
				local in_code_block = false
				for _, l in ipairs(vim.split(item.content, "\n", { plain = true })) do
					if l:match("^```") then
						table.insert(content_with_code_blocks, l)
						in_code_block = not in_code_block
					else
						-- 如果在代码块内，不缩进
						if in_code_block then
							table.insert(content_with_code_blocks, l)
						else
							table.insert(content_with_code_blocks, "  " .. l) -- 正常文本缩进
						end
					end
				end
				-- 如果内容最后没有结束代码块，确保它不会影响后续文本的缩进
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
			table.insert(lines, "") -- 在每个分隔线后也加一个空行，让视觉更清晰
		end
	end

	-- 第二部分：分隔符和即将发送给AI的prompt列表
	table.insert(lines, string.rep("=", 40))
	table.insert(
		lines,
		string.format("**--- Messages to be sent to AI (Max %d) ---**", config.config.history.chat_max_count)
	)
	table.insert(lines, "")

	if #messages_to_ai == 0 then
		table.insert(lines, "No messages will be sent.")
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
	table.insert(lines, "") -- 结尾也加个空行

	return lines
end

function M.insertHistory(role, content)
	table.insert(M.chat_history, {
		role = role,
		content = content,
		time = os.date("%Y-%m-%d %H:%M:%S"),
	})
	-- 如果历史记录超过某个限制，移除最旧的
	if #M.chat_history > config.config.history.max_save_count then
		table.remove(M.chat_history, 1)
	end

	local messages = {}
	for i = math.max(1, #M.chat_history - config.config.history.chat_max_count), #M.chat_history do
		table.insert(messages, {
			role = M.chat_history[i].role,
			content = M.chat_history[i].content,
		})
	end

	-- 如果历史窗口是打开的，就更新它
	-- 这样可以实现实时更新，而不是每次都手动调用 showHistory
	if M.history_win_id and vim.api.nvim_win_is_valid(M.history_win_id) then
		-- 重新计算并更新窗口内容，保持在当前窗口显示
		local lines = format_history_lines(M.chat_history, messages)
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
	-- 如果历史窗口开着，也关掉
	if M.history_win_id and vim.api.nvim_win_is_valid(M.history_win_id) then
		vim.api.nvim_win_close(M.history_win_id, true)
		M.history_win_id = nil
		M.history_buf_id = nil
	end
	vim.notify("History is clear")
end

-- 创建并显示浮动窗口
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

	-- 计算出即将发送给AI的messages列表
	local messages_to_ai = {}
	if #M.chat_history > 0 then -- 确保有历史记录才计算
		for i = math.max(1, #M.chat_history - config.config.history.chat_max_count), #M.chat_history do
			table.insert(messages_to_ai, {
				role = M.chat_history[i].role,
				content = M.chat_history[i].content,
			})
		end
	end

	local lines = format_history_lines(M.chat_history, messages_to_ai) -- 传入两部分数据
	local win_id, buf = create_history_window(lines) -- create_history_window 不需要改动

	M.history_win_id = win_id
	M.history_buf_id = buf
end

function M.save_history()
	local history_path = vim.fn.stdpath("data") .. "/ai_chat_history.json"
	local ok, err = pcall(function()
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
			vim.notify("History has been loaded", vim.log.levels.INFO)
		else
			vim.notify("Load History failed ro invalid content.", vim.log.levels.WARN)
			M.chat_history = {} -- 防止加载失败导致 chat_history 为 nil 或错误类型
		end
	else
		vim.notify("No History file and new one created.", vim.log.levels.INFO)
		M.chat_history = {}
	end
end

return M
