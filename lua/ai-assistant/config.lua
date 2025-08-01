local M = {}
-- 默认配置
M.defaults = {
	enabled = true,
	window = {
		width = 0.6,
		height = 0.8,
		split_ratio = 0.2,
	},
	keymaps = {
		open_chat = "<leader>dc",
		submit = "<C-Enter>",
		show_history = "<leader>dh",
		clear_history = "<leader>ddh",
		clear_prompt = "<leader>ddp",
		chat_current_line = "<leader>drl",
		chat_file = "<leader>drf",
		select_model = "<leader>ds",
	},
	apis = {
		google_gemini = {
			api_url = "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions",
			api_key = os.getenv("GEMINI_API_KEY"),
			model = "gemini-2.5-flash",
			available_models = {
				"gemini-2.5-flash",
				"gemini-2.5-pro",
			},
		},
		aliyun_qwen = {
			api_url = "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions",
			api_key = os.getenv("DASHSCOPE_API_KEY"),
			model = "qwen-plus",
			available_models = {
				"qwen-plus",
				"qwen-max",
				"qwen-turbo",
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
	},
	select_model = "google_gemini",
	history = {
		max_save_count = 20,
		chat_max_count = 10,
	},
	max_context_lines = 1000,
	max_prompt_tokens = 5000,
	max_prompt_token_ratio = 2, -- English:3.5, Chines 2 or 2.5
}

M.config = {}

function M.setup(opts)
	M.config = vim.tbl_deep_extend("force", {}, M.defaults, opts or {})

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
