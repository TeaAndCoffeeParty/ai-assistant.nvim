local M = { chat_history = {} }

local config = require("deepseek.config")

M.history_win_id = nil
M.history_buf_id = nil

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
	vim.notify("对话历史已清空")
end

-- 格式化历史记录为 markdown 行
local function format_history_lines(chat_history)
	local lines = {}
	for _, item in ipairs(chat_history) do
		table.insert(lines, string.format("**[%s] %s:**", item.time or "", item.role or ""))
		if item.content then
			local content_lines = vim.split(item.content, "\n", { plain = true })
			for _, l in ipairs(content_lines) do
				table.insert(lines, l)
			end
		else
			table.insert(lines, "")
		end
		table.insert(lines, string.rep("-", 40))
	end
	if #lines == 0 then
		table.insert(lines, "暂无历史记录")
	end
	return lines
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

	local lines = format_history_lines(M.chat_history)
	local win_id, buf = create_history_window(lines)
	M.history_win_id = win_id
	M.history_buf_id = buf
end

function M.save_history()
	local history_path = vim.fn.stdpath("data") .. "/ai_chat_history.json"
	local ok, err = pcall(function()
		vim.fn.writefile({ vim.fn.json_encode(M.chat_history) }, history_path)
	end)
	if not ok then
		vim.notify("保存历史记录失败: " .. err, vim.log.levels.ERROR)
	else
		vim.notify("历史记录已保存到: " .. history_path, vim.log.levels.INFO)
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
			vim.notify("历史记录已从 " .. history_path .. " 加载", vim.log.levels.INFO)
		else
			vim.notify("加载历史记录失败或文件内容无效。", vim.log.levels.WARN)
			M.chat_history = {} -- 防止加载失败导致 chat_history 为 nil 或错误类型
		end
	else
		vim.notify("历史记录文件不存在，将创建新的历史记录。", vim.log.levels.INFO)
		M.chat_history = {}
	end
end

return M
