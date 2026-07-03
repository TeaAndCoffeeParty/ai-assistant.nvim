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

	-- 扫描所有 provider，找出「可用」的（api_key + api_url + model 都配了）
	local available_providers = {}
	local missing_current = {}
	for name, api_conf in pairs(M.config.apis) do
		local ok = true
		if not (type(api_conf.api_key) == "string" and #api_conf.api_key > 0) then
			ok = false
			if name == M.config.select_model then
				table.insert(missing_current, "api_key 未设置")
			end
		end
		if not api_conf.api_url then
			ok = false
			if name == M.config.select_model then
				table.insert(missing_current, "api_url 未配置")
			end
		end
		if not api_conf.model then
			ok = false
			if name == M.config.select_model then
				table.insert(missing_current, "model 未配置")
			end
		end
		if ok then
			table.insert(available_providers, name)
		end
	end

	-- 当前选中的 provider 配置不完整：尝试自动切换到一个可用的
	if #missing_current > 0 then
		local old_provider = M.config.select_model
		if #available_providers > 0 then
			-- 自动切换到第一个可用的 provider
			local fallback = available_providers[1]
			M.config.select_model = fallback
			model_config = M.config.apis[fallback]
			vim.notify(
				string.format(
					"当前 provider [%s] 配置不全（%s），已自动切换为 [%s] → %s。可用 :AiSelectModel 手动切换。",
					old_provider,
					table.concat(missing_current, "、"),
					fallback,
					model_config.model
				),
				vim.log.levels.WARN,
				{ title = "AI Chat" }
			)
		else
			-- 没有任何可用的 provider，发出警告但不阻断加载
			vim.notify(
				string.format(
					"当前 provider [%s] 配置不全（%s），且未检测到其它可用的 provider。\n"
						.. "请设置至少一个 provider 的 api_key（环境变量或在 setup() 中传入），然后用 :AiSelectModel 切换。",
					M.config.select_model,
					table.concat(missing_current, "、")
				),
				vim.log.levels.WARN,
				{ title = "AI Chat" }
			)
		end
	elseif #available_providers > 1 then
		-- 当前 provider 配置完整，且还有其他可用 provider，静默加载
		vim.notify(
			string.format(
				"当前 [%s] → %s（另有 %d 个可用 provider，:AiSelectModel 切换）",
				M.config.select_model,
				model_config.model,
				#available_providers - 1
			),
			vim.log.levels.INFO,
			{ title = "AI Chat" }
		)
	end

	-- 设置快捷键,命令
	commands.setup(M)

	history.load_history()
	if M.config.history.isolate_context_after_load then
		history.resetPromptContext({ silent = true })
		vim.notify(
			"已按配置重置发给 API 的上下文（磁盘里的旧对话不会参与请求）。",
			vim.log.levels.INFO,
			{ title = "AI Chat" }
		)
	end

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

function M.chat_folder_with_input()
	-- 使用 vim.ui.input 获取用户输入
	vim.ui.input({
		prompt = "Enter folder path (default: current directory): ",
		default = ".",
		completion = "dir", -- 启用目录补全
	}, function(input)
		if input ~= nil then -- 用户按了 Enter，不是 Esc
			local folder_path = input ~= "" and input or "."
			M.chat_with_context("folder_content", folder_path)
		end
	end)
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

		local prev_provider = M.config.select_model
		local prev_model = nil
		if prev_provider and M.config.apis[prev_provider] then
			prev_model = M.config.apis[prev_provider].model
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
					config.save_persisted_selection()
					local msg = string.format("已切换为 %s → %s（已写入配置）", selected_provider, selected_model_name)
					if prev_provider ~= selected_provider or prev_model ~= selected_model_name then
						history.resetPromptContext({ silent = true })
						msg = msg .. "\n已重置「发给 API 的上下文」，避免旧对话里其它模型的人设影响当前模型。"
					end
					vim.notify(msg, vim.log.levels.INFO, { title = "AI Chat" })
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
	local full_thinking = ""
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

	window.echo_user_input(input_data.raw_input_lines)
	window.reset_assistant_stream_kind()

	request_api.query_stream(messages, {
		on_data = function(content, kind)
			if not content or content == "" then
				return
			end
			if kind == "thinking" then
				full_thinking = full_thinking .. content
				window.safe_buf_update(content, "thinking")
			else
				full_response = full_response .. content
				window.safe_buf_update(content, "content")
			end
		end,
		on_finish = function()
			if full_response:match("^%s*$") then
				vim.notify(
					"模型返回为空。请确认 API、模型名与网络；若服务端返回了 HTTP 非 200，插件现在会提示错误。",
					vim.log.levels.WARN,
					{ title = "AI Chat" }
				)
			end
			local hist_assistant = full_response
			if full_thinking ~= "" then
				hist_assistant = "**Thinking**\n\n> "
					.. full_thinking:gsub("\n", "\n> ")
					.. "\n\n---\n\n"
					.. full_response
			end
			history.insertHistory("assistant", hist_assistant)

			window.safe_buf_update("\n\nTimestamp:" .. os.date("%Y-%m-%d %H:%M:%S"))
			window.safe_buf_update("\n\n-------------------\n")
			--清空输入区
			vim.api.nvim_buf_set_lines(state.input_buf, 0, -1, false, { "" })
			vim.api.nvim_set_current_win(state.output_win)
			vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", false)
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
