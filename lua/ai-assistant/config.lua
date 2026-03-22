local M = {}
-- 默认配置
M.defaults = {
	enabled = true,
	window = {
		--- "split"：右侧固定列宽分栏（类似 Cursor 侧栏，用 Ctrl-w w 与编辑区切换）
		--- "float"：居中靠右的浮动窗口（旧版行为）
		layout = "split",
		--- layout 为 split 时侧栏宽度（列数 / characters）
		sidebar_width = 80,
		width = 0.6,
		height = 0.8,
		split_ratio = 0.22,
	},
	apis = {
		google_gemini = {
			api_url = "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions",
			api_key = os.getenv("GEMINI_API_KEY"),
			model = "gemini-3-flash-preview",
			available_models = {
				"gemini-3-flash-preview",
				"gemini-2.5-flash",
			},
		},
		aliyun_qwen = {
			api_url = "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions",
			api_key = os.getenv("DASHSCOPE_API_KEY"),
			model = "qwen3.5-plus",
			available_models = {
				"qwen3.5-plus",
				"qwen3.5-flash",
			},
		},
		deepseek = {
			api_url = "https://api.deepseek.com/v1/chat/completions",
			api_key = os.getenv("DEEPSEEK_API_KEY"),
			model = "deepseek-chat",
			available_models = {
				"deepseek-chat",
				"deepseek-coder",
			},
		},
		moonshot = {
			api_url = "https://api.moonshot.cn/v1/chat/completions",
			api_key = os.getenv("MOONSHOT_API_KEY"),
			model = "kimi-k2-0711-preview",
			available_models = {
				"kimi-k2-0711-preview",
			},
		},
		modelscope = {
			api_url = "https://api-inference.modelscope.cn/v1/chat/completions",
			api_key = os.getenv("MODELSCOPE_API_KEY"),
			model = "deepseek-ai/DeepSeek-V3.2",
			available_models = {
				"deepseek-ai/DeepSeek-V3.2",
				"qwen/qwen3-coder-480b-a35b-instruct",
			},
		},
	},
	select_model = "modelscope",
	history = {
		max_save_count = 20,
		chat_max_count = 10,
		--- 为 true：每次启动加载 ai_chat_history.json 后，不把旧对话发给 API（等同 :ChatClearPrompt），避免换模型后人设仍被旧 assistant 带偏
		isolate_context_after_load = false,
	},
	max_context_lines = 1000,
	max_prompt_tokens = 5000,
	max_prompt_token_ratio = 2, -- English:3.5, Chines 2 or 2.5
	--- 为 true 时：在 UI 中选择模型后会写入 data 目录，下次启动自动恢复
	persist_selection = true,
}

M.config = {}

local function selection_state_path()
	return vim.fn.stdpath("data") .. "/ai-assistant-selection.json"
end

--- 从上次会话恢复选中的 provider 与各 API 的 model（仅当 persist_selection 为 true）
function M.load_persisted_selection()
	if not M.config.persist_selection then
		return
	end
	local path = selection_state_path()
	local f = io.open(path, "r")
	if not f then
		return
	end
	local raw = f:read("*a")
	f:close()
	local ok, decoded = pcall(vim.json.decode, raw)
	if not ok or type(decoded) ~= "table" then
		return
	end
	if type(decoded.select_model) == "string" and M.config.apis[decoded.select_model] then
		M.config.select_model = decoded.select_model
	end
	if type(decoded.api_models) == "table" then
		for api_name, model_name in pairs(decoded.api_models) do
			local api_conf = M.config.apis[api_name]
			if api_conf and type(model_name) == "string" and api_conf.available_models then
				local found = false
				for _, available_m in ipairs(api_conf.available_models) do
					if available_m == model_name then
						found = true
						break
					end
				end
				if found then
					api_conf.model = model_name
				end
			end
		end
	end
end

--- 将当前 select_model 与各 apis.*.model 写入磁盘
function M.save_persisted_selection()
	if not M.config.persist_selection then
		return
	end
	local api_models = {}
	for api_name, api_conf in pairs(M.config.apis) do
		if type(api_conf.model) == "string" and api_conf.model ~= "" then
			api_models[api_name] = api_conf.model
		end
	end
	local payload = vim.json.encode({
		select_model = M.config.select_model,
		api_models = api_models,
	})
	local path = selection_state_path()
	vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
	local f, open_err = io.open(path, "w")
	if not f then
		vim.notify(
			"无法保存模型选择: " .. tostring(open_err or path),
			vim.log.levels.WARN,
			{ title = "AI Chat" }
		)
		return
	end
	f:write(payload)
	f:close()
end

function M.setup(opts)
	M.config = vim.tbl_deep_extend("force", {}, M.defaults, opts or {})

	M.load_persisted_selection()

	-- 确保每个API的默认模型在可用模型列表中
	for api_name, api_conf in pairs(M.config.apis) do
		if api_conf.model and api_conf.available_models then
			local found = false
			for _, available_m in ipairs(api_conf.available_models) do
				if available_m == api_conf.model then
					found = true
					break
				end
			end
			if not found then
				-- 如果默认模型不在可用列表中，则将第一个可用模型设为默认
				if #api_conf.available_models > 0 then
					api_conf.model = api_conf.available_models[1]
					print(
						string.format(
							"Warning: Default model '%s' for '%s' not found in available_models. Setting to '%s'.",
							api_conf.model,
							api_name,
							api_conf.available_models[1]
						)
					)
				else
					api_conf.model = nil -- 没有可用模型
					print(string.format("Warning: No available models defined for '%s'.", api_name))
				end
			end
		end
	end

	return M.config
end

function M.get_model()
	if not M.config.select_model then
		return nil, "No selected model"
	end

	local selected_api = M.config.select_model
	local api_config = M.config.apis[selected_api]

	if not api_config then
		return nil, string.format("API configuration for %s does not exist.", selected_api)
	end

	return api_config, nil
end

-- 设置特定API提供商的当前模型
function M.set_api_model(api_name, model_name)
	if not M.config.apis[api_name] then
		return false, string.format("API provider '%s' does not exist.", api_name)
	end

	local api_conf = M.config.apis[api_name]
	if not api_conf.available_models then
		return false, string.format("API provider '%s' has no available models defined.", api_name)
	end

	local found = false
	for _, available_m in ipairs(api_conf.available_models) do
		if available_m == model_name then
			found = true
			break
		end
	end

	if not found then
		return false,
			string.format(
				"Model '%s' is not available for API provider '%s'. Available models: %s",
				model_name,
				api_name,
				table.concat(api_conf.available_models, ", ")
			)
	end

	api_conf.model = model_name
	return true, nil
end

return M
