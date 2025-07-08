local M = {}

function M.setup(opts)
	-- 合并默认配置和用户配置
	M.config = vim.tbl_deep_extend("force", {
		-- 默认配置
		enabled = true,
		some_option = "default",
	}, opts or {})

	-- 如果插件被禁用则返回
	if not M.config.enabled then
		return
	end

	-- 在这里添加你的插件逻辑
	vim.notify("My LazyVim 插件已加载!")
end

return M
