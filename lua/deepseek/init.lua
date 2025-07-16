local M = {
	chat_history = {},
	current_session_id = nil,
}

local window = require("deepseek.window")
local config = require("deepseek.config")

function M.setup(opts)
	-- 合并默认配置和用户配置
	M.config = config.setup(opts)

	-- 如果插件被禁用则返回
	if not M.config.enabled then
		vim.notify("DeepSeek插件已禁用")
		return
	end

	local model_config, err = config.get_model()

	if err or not model_config then
		error("获取模型配置失败: " .. (err or "未知错误"))
	end

	-- 关键配置验证
	assert(
		type(model_config.api_key) == "string" and #model_config.api_key > 0,
		"必须配置 DeepSeek API Key (通过 setup() 或环境变量 DEEPSEEK_API_KEY)"
	)
	assert(model_config.api_url, "必须配置 api_url")
	assert(model_config.model, "必须配置 model")

	-- 设置快捷键,命令
	M.setup_commands()

	-- 在这里添加你的插件逻辑
	vim.notify("DeepSeek插件已加载!")
end

-- 设置快捷键函数
function M.setup_commands()
	vim.api.nvim_create_user_command("DeepSeekClearHistory", function()
		M.chat_history = {}
		vim.notify("对话历史已清空")
	end, {})

	vim.api.nvim_create_user_command("DeepSeekShowHistory", function()
		print(vim.inspect(M.chat_history))
	end, {})

	vim.api.nvim_create_user_command("DeepSeek", function()
		M.open_chat_ui()
	end, {})

	vim.keymap.set("n", M.config.keymaps.open_chat, function()
		M.open_chat_ui()
	end, { desc = "打开 DeepSeek 聊天窗口" })

	vim.keymap.set(
		"n",
		M.config.keymaps.show_history,
		":DeepSeekShowHistory<CR>",
		{ desc = "Show DeepSeek Chat History" }
	)
	vim.keymap.set(
		"n",
		M.config.keymaps.clear_history,
		":DeepSeekClearHistory<CR>",
		{ desc = "Clear DeepSeek Chat History" }
	)
end

-- 打开聊天窗口
function M.open_chat_ui()
	local win_state = window.create(M.config.window)
end

function M.close_windows()
	window.close()
end

function M.submit_input()
	local state = window.get_state()
	local user_input = window.get_input()
	if not user_input then
		return
	end

	--	local user_content = table.concat(user_input.display_lines, "\n")
	table.insert(M.chat_history, {
		role = "user",
		content = user_input.prompt,
		time = os.date("%Y-%m-%d %H:%M:%S"),
	})

	window.echo_user_input(user_input.display_lines)

	local full_response = ""
	local messages = {}
	for i = math.max(1, #M.chat_history - 10), #M.chat_history do
		table.insert(messages, {
			role = M.chat_history[i].role,
			content = M.chat_history[i].content,
		})
	end

	require("deepseek.api").query_stream(messages, {
		on_data = function(content)
			if content then
				full_response = full_response .. content
				window.safe_buf_update(content)
			end
		end,
		on_finish = function()
			table.insert(M.chat_history, {
				role = "assistant",
				content = full_response,
				time = os.date("%Y-%m-%d %H:%M:%S"),
			})

			window.safe_buf_update("\n\n当前时间：" .. os.date("%Y-%m-%d %H:%M:%S"))
			window.safe_buf_update("\n\n-------------------\n")
			--清空输入区
			vim.api.nvim_buf_set_lines(state.input_buf, 0, -1, false, { "" })
			vim.api.nvim_win_set_cursor(state.input_win, { 1, 0 })
			vim.cmd("startinsert!")
			vim.bo[state.output_buf].filetype = "markdown"
		end,
		on_error = function(err)
			window.safe_buf_update("\n\n[ERROR] " .. tostring(err))
			window.safe_buf_update("\n当前时间：" .. os.date("%Y-%m-%d %H:%M:%S"))
			window.safe_buf_update("\n\n-------------------\n")
			vim.api.nvim_buf_set_lines(state.input_buf, 0, -1, false, { "" })
			vim.bo[state.output_buf].filetype = "markdown"
		end,
	})
end

function M.save_history()
	local history_path = vim.fn.stdpath("data") .. "/deepseek_history.json"
	local data = {
		sessions = {
			[M.current_session_id or "default"] = M.chat_history,
		},
	}
	vim.fn.writefile({ vim.fn.json_encode(data) }, history_path)
end

function M.load_history()
	local history_path = vim.fn.stdpath("data") .. "/deepseek_history.json"
	if vim.fn.filereadable(history_path) == 1 then
		local data = vim.fn.json_decode(vim.fn.readfile(history_path))
		if data.sessions and data.sessions[M.current_session_id or "default"] then
			M.chat_history = data.sessions[M.current_session_id or "default"]
		end
	end
end

return M
