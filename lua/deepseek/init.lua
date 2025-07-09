local M = {}

local window = require("deepseek.window")

-- 默认配置
local defaults = {
	enabled = true,
	window = {
		width = 80,
		height = 40,
		split_ratio = 0.2,
	},
	keymaps = {
		open_chat = "<leader>dc",
		submit = "<C-Enter>",
	},
}

function M.setup(opts)
	-- 合并默认配置和用户配置
	M.config = vim.tbl_deep_extend("force", {
		api_url = "https://api.deepseek.com/v1/chat/completions",
		model = "deepseek-chat",
		timeout = 30000,
	}, defaults, opts or {})

	-- 如果插件被禁用则返回
	if not M.config.enabled then
		vim.notify("DeepSeek插件已禁用")
		return
	end

	-- 关键配置验证
	assert(
		type(M.config.api_key) == "string" and #M.config.api_key > 0,
		"必须配置 DeepSeek API Key (通过 setup() 或环境变量 DEEPSEEK_API_KEY)"
	)

	-- 设置快捷键
	M.setup_keymaps()

	-- 在这里添加你的插件逻辑
	vim.notify("DeepSeek插件已加载!")
end

-- 设置快捷键函数
function M.setup_keymaps()
	vim.keymap.set("n", M.config.keymaps.open_chat, function()
		M.open_chat_ui()
	end, { desc = "打开 DeepSeek 聊天窗口" })
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

	window.safe_buf_update({
		table.concat(user_input.display_lines, "\n"),
		"",
		"-------------------",
	})

	require("deepseek.api").query(user_input.prompt, function(response)
		window.safe_buf_update({
			vim.trim(response),
			"",
			"当前时间：" .. os.date("%Y-%m-%d %H:%M:%S"),
			"-------------------",
		})

		--清空输入区
		vim.api.nvim_buf_set_lines(state.input_buf, 0, -1, false, { "" })
		vim.api.nvim_win_set_cursor(state.input_win, { 1, 0 })
		vim.cmd("startinsert!")
	end)
end

return M
