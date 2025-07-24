local M = {}
-- 默认配置
M.defaults = {
	enabled = true,
	window = {
		width = 80,
		height = 40,
		split_ratio = 0.2,
	},
	keymaps = {
		open_chat = "<leader>dc",
		submit = "<C-Enter>",
		show_history = "<leader>dh",
		clear_history = "<leader>dd",
	},
	apis = {
		google_gemini = {
			api_url = "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions",
			api_key = os.getenv("GEMINI_API_KEY"),
			model = "gemini-2.5-flash",
		},
		aliyun_qwen = {
			api_url = "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions",
			api_key = os.getenv("DASHSCOPE_API_KEY"),
			model = "qwen-plus",
		},
		deepseek = {
			api_url = "https://api.deepseek.com/v1/chat/completions",
			api_key = os.getenv("DEEPSEEK_API_KEY"),
			model = "deepseek-chat",
		},
	},
	select_model = "google_gemini",
	history = {
		max_save_count = 20,
		chat_max_count = 10,
	},
}

M.config = {}

function M.setup(opts)
	M.config = vim.tbl_deep_extend("force", {}, M.defaults, opts or {})
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

return M
