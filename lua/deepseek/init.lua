local M = {}

local window = require("deepseek.window")
local config = require("deepseek.config")
local history = require("deepseek.history")

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
	end, {})

	vim.api.nvim_create_user_command("ChatShowHistory", function()
		history.showHistory()
	end, {})

	vim.api.nvim_create_user_command("Chat", function()
		M.open_chat_ui()
	end, {})

	vim.api.nvim_create_user_command("ChatVisual", function()
		M.send_visual_selection()
	end, { range = true })

	vim.keymap.set("n", M.config.keymaps.open_chat, function()
		M.open_chat_ui()
	end, { desc = "Open AI Chat Window" })

	vim.keymap.set("v", M.config.keymaps.open_chat, ":ChatVisual<CR>", { desc = "Send Selected Content to Chat" })
	vim.keymap.set("n", M.config.keymaps.show_history, ":ChatShowHistory<CR>", { desc = "Show Chat Chat History" })
	vim.keymap.set("n", M.config.keymaps.clear_history, ":ChatClearHistory<CR>", { desc = "Clear Chat Chat History" })
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
	local win_state = window.create(M.config.window)
end

-- 处理Visual模式选择的内容
function M.send_visual_selection()
	-- 获取选择的文本
	local visual_selection = vim.fn.getline("'<", "'>")
	if not visual_selection or #visual_selection == 0 then
		vim.notify("Nothing has been selected", vim.log.levels.WARN)
		return
	end

	-- 打开聊天窗口
	M.open_chat_ui()

	-- 等待窗口创建完成
	vim.defer_fn(function()
		local state = window.get_state()
		if state and state.input_buf then
			-- 将选中的内容填入输入区
			vim.api.nvim_buf_set_lines(state.input_buf, 0, -1, false, visual_selection)

			-- 将光标移到输入区末尾，允许用户继续编辑
			local line_count = #visual_selection
			vim.api.nvim_win_set_cursor(state.input_win, { line_count, #visual_selection[line_count] })
		end
	end, 100)
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

	window.echo_user_input(user_input.raw_input_lines)

	local full_response = ""
	local messages = history.insertHistory("user", user_input.prompt)

	require("deepseek.api").query_stream(messages, {
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
		end,
	})
end

return M
