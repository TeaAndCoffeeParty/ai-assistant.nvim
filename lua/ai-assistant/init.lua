local M = {}

local window = require("ai-assistant.window")
local config = require("ai-assistant.config")
local history = require("ai-assistant.history")
local request_api = require("ai-assistant.api")
local commands = require("ai-assistant.commands")
local context = require("ai-assistant.context")

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
	commands.setup(M, history)

	history.load_history()

	context.setup(M, window)
	-- 在这里添加你的插件逻辑
	vim.notify(model_config.model .. " has benn loaded!")
end

-- 打开聊天窗口
function M.open_chat_ui()
	window.create(M.config.window)
end

M.chat_with_context = function(mode, start_line, end_line)
	return context.chat_with_context(mode, start_line, end_line)
end

function M.select_ai_model()
	local available_providers = {}
	for provider_name, _ in pairs(M.config.apis) do
		table.insert(available_providers, provider_name)
	end

	if #available_providers == 0 then
		vim.notify("No AI model providers configured.", vim.log.levels.WARN, { title = "AI Chat Warning" })
		return
	end

	-- Step 1: Select AI Provider
	vim.ui.select(available_providers, {
		prompt = "Select AI Provider:",
		kind = "ai_provider_selector",
		format_item = function(item)
			return item .. (item == M.config.select_model and " (current)" or "")
		end,
	}, function(selected_provider)
		if not selected_provider then
			vim.notify("Provider selection cancelled.", vim.log.levels.INFO, { title = "AI Chat" })
			return
		end

		-- Update the globally selected provider first
		M.config.select_model = selected_provider

		local api_config = M.config.apis[selected_provider]
		if not api_config or not api_config.available_models or #api_config.available_models == 0 then
			vim.notify(
				string.format("No models available for provider: %s", selected_provider),
				vim.log.levels.WARN,
				{ title = "AI Chat Warning" }
			)
			return
		end

		local models_for_current_provider = api_config.available_models

		-- Step 2: Select Specific Model for the chosen Provider
		vim.ui.select(models_for_current_provider, {
			prompt = string.format("Select Model for %s:", selected_provider),
			kind = "ai_model_selector_for_provider",
			format_item = function(item)
				return item .. (item == api_config.model and " (current)" or "")
			end,
		}, function(selected_model_name)
			if selected_model_name then
				local success, err = config.set_api_model(selected_provider, selected_model_name)
				if success then
					vim.notify(
						string.format("AI Model switched to: %s -> %s", selected_provider, selected_model_name),
						vim.log.levels.INFO,
						{ title = "AI Chat" }
					)
				else
					vim.notify(
						string.format("Failed to set model for %s: %s", selected_provider, err),
						vim.log.levels.ERROR,
						{ title = "AI Chat Error" }
					)
				end
			else
				vim.notify(
					string.format("Model selection for %s cancelled.", selected_provider),
					vim.log.levels.INFO,
					{ title = "AI Chat" }
				)
			end
		end)
	end)
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

	local full_response = ""
	local messages = history.insertHistory("user", input_data.full_prompt)

	local send_tokens = context.calculate_total_tokens(messages, 4)
	if send_tokens > M.config.max_prompt_tokens then
		local msg = string.format(
			"Your prompt is estimated to be %d tokens, which exceeds the configured limit of %d tokens.\n"
				.. "Sending very large prompts may incur higher costs or hit model context limits.\n"
				.. "Do you want to send it anyway?(Input 1[Confirm], 2[Cancel])",
			send_tokens,
			M.config.max_prompt_tokens
		)
		local choice = vim.fn.confirm(msg, "1:Yes\n2:No", 2) -- 默认选择 "No"
		if choice ~= 1 then -- 如果用户没有选择 "Yes"
			vim.notify("Prompt submission cancelled.", vim.log.levels.INFO)
			return
		end
	end

	vim.notify("Querying AI...", vim.log.levels.INFO, { title = "AI Chat" })
	window.echo_user_input(input_data.raw_input_lines)

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
