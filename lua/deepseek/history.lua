local M = { chat_history = {} }

local config = require("deepseek.config")

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
	vim.notify("对话历史已清空")
end

function M.showHistory()
	print(vim.inspect(M.chat_history))
end

function M.save_history()
	local history_path = vim.fn.stdpath("data") .. "/ai_chat_history.json"
	vim.fn.writefile({ vim.fn.json_encode(M.chat_history) }, history_path)
end

function M.load_history()
	local history_path = vim.fn.stdpath("data") .. "/ai_chat_history.json"
	if vim.fn.filereadable(history_path) == 1 then
		local data = vim.fn.json_decode(vim.fn.readfile(history_path))
		M.chat_history = data
	end
end

return M
