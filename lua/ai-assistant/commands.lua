local M = {}

-- 设置快捷键函数
function M.setup(main_plugin, history_module)
	local history = history_module
	local P = main_plugin

	vim.api.nvim_create_user_command("ChatClearHistory", function()
		history.clearHistory()
		vim.notify("AI Chat history cleared")
	end, { desc = "Clear AI Chat History" })

	vim.api.nvim_create_user_command("ChatClearPrompt", function()
		history.resetPromptContext()
		vim.notify("AI Chat prompt context cleared")
	end, { desc = "Clear AI Chat Prompt Context" })

	vim.api.nvim_create_user_command("ChatShowHistory", function()
		history.showHistory()
	end, { desc = "Show AI Chat History" })

	vim.api.nvim_create_user_command("Chat", function()
		P.open_chat_ui()
	end, { desc = "Show AI Chat Window" })

	-- 新增命令: 引用当前行
	vim.api.nvim_create_user_command("ChatCurrentLine", function()
		P.chat_with_context("current_line")
	end, { desc = "Send Current Line to AI Chat" })

	-- 新增命令: 引用整个文件
	vim.api.nvim_create_user_command("ChatFile", function()
		P.chat_with_context("file_full")
	end, { desc = "Send Entire File to AI Chat" })

	-- 新增命令: 引用指定行范围
	-- :ChatRange <start_line> <end_line>
	vim.api.nvim_create_user_command("ChatRange", function(opts)
		local start_line = tonumber(opts.fargs[1])
		local end_line = tonumber(opts.fargs[2])
		if not start_line or not end_line or start_line <= 0 or end_line <= 0 or start_line > end_line then
			vim.notify("Usage: :ChatRange <start_line> <end_line>", vim.log.levels.ERROR)
			return
		end
		P.chat_with_context("file_range", start_line, end_line)
	end, { nargs = "*", desc = "Send File Range to AI Chat" })

	-- 统一 ChatVisual 命令，调用 P.chat_with_context
	vim.api.nvim_create_user_command("ChatVisual", function()
		P.chat_with_context("visual_selection")
	end, { range = true, desc = "Send Visual Selection to AI Chat" })

	vim.api.nvim_create_user_command("ChatSelectModel", function()
		P.select_ai_model()
	end, { desc = "Select AI Model" })

	vim.keymap.set("n", P.config.keymaps.open_chat, function()
		P.open_chat_ui()
	end, { desc = "Open AI Chat Window" })

	vim.keymap.set("v", P.config.keymaps.open_chat, ":ChatVisual<CR>", { desc = "Send Selected Content to Chat" })

	vim.keymap.set(
		"n",
		P.config.keymaps.chat_current_line,
		":ChatCurrentLine<CR>",
		{ desc = "Send Current Line to Chat" }
	)
	vim.keymap.set("n", P.config.keymaps.chat_file, ":ChatFile<CR>", { desc = "Send Entire File to Chat" })

	vim.keymap.set("n", P.config.keymaps.show_history, ":ChatShowHistory<CR>", { desc = "Show Chat History" })
	vim.keymap.set("n", P.config.keymaps.clear_history, ":ChatClearHistory<CR>", { desc = "Clear Chat History" })
	vim.keymap.set("n", P.config.keymaps.clear_prompt, ":ChatClearPrompt<CR>", { desc = "Clear Chat Prompt History" })
	vim.keymap.set("n", P.config.keymaps.select_model, ":ChatSelectModel<CR>", { desc = "Select AI Model" })

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

return M
