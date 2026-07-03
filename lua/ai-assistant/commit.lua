local M = {}

local api = require("ai-assistant.api")

--- 获取 git 仓库根目录
---@return string|nil
local function get_git_root()
	local git_root = vim.fn.systemlist("git rev-parse --show-toplevel")[1]
	if vim.v.shell_error ~= 0 then
		vim.notify("不在 git 仓库中", vim.log.levels.ERROR, { title = "ChatCommit" })
		return nil
	end
	return git_root
end

--- 获取暂存区 diff
---@param git_root string
---@return string|nil
local function get_staged_diff(git_root)
	local cmd = 'cd "' .. git_root .. '" && git diff --cached'
	local staged_diff = vim.fn.system(cmd)
	if vim.v.shell_error ~= 0 then
		vim.notify("获取 staged diff 失败", vim.log.levels.ERROR, { title = "ChatCommit" })
		return nil
	end
	if staged_diff == "" or staged_diff:match("^%s*$") then
		vim.notify("没有暂存的修改，请先执行 'git add'", vim.log.levels.WARN, { title = "ChatCommit" })
		return nil
	end
	return staged_diff
end

--- 获取未暂存的 diff（仅作为上下文参考，不会被提交）
---@param git_root string
---@return string
local function get_unstaged_diff(git_root)
	local cmd = 'cd "' .. git_root .. '" && git diff'
	local unstaged = vim.fn.system(cmd)
	if vim.v.shell_error ~= 0 then
		return ""
	end
	return unstaged
end

--- 构建发送给 AI 的 prompt
---@param staged_diff string
---@param unstaged_diff string
---@return string
local function build_prompt(staged_diff, unstaged_diff)
	local prompt = [[你是一个专业的代码审查者，请根据以下 git diff 生成一条符合 conventional commits 规范的提交消息。

## 暂存的修改（将被提交）
```diff
]]
		.. staged_diff
		.. "```\n\n"

	-- 如果有未暂存的修改，也附上作为上下文（让 AI 了解完整的改动背景）
	if unstaged_diff ~= "" and #unstaged_diff < 20000 then
		prompt = prompt
			.. [[## 未暂存的修改（仅供参考上下文，不会被提交）
```diff
]]
			.. unstaged_diff
			.. "```\n\n"
	end

	prompt = prompt
		.. [[## 要求
- 严格遵循 conventional commits 格式：<type>(<scope>): <description>
- type 类型：feat, fix, docs, style, refactor, perf, test, chore, ci, build, revert
- 标题行控制在 50 个字符以内
- 正文每行不超过 72 个字符
- 聚焦于改了什么 (WHAT) 和为什么改 (WHY)，而非怎么改
- 标题和正文之间空一行
- 如果修改涉及多个不相关的功能，建议拆分为多个 commit
- **只输出提交消息本身，不要有任何解释、标记或代码围栏**]]

	return prompt
end

--- 清理 AI 回复中的多余标记
---@param raw string
---@return string
local function clean_commit_message(raw)
	local msg = raw
		:gsub("^```[^\n]*\n", "") -- 移除开头代码围栏
		:gsub("\n```$", "") -- 移除结尾代码围栏
		:gsub("^%s+", "") -- 去除开头空白
		:gsub("%s+$", "") -- 去除结尾空白

	return msg
end

--- 处理生成的提交消息：保存到 COMMIT_EDITMSG + 剪贴板
---@param commit_msg string
---@param git_root string
local function handle_commit_message(commit_msg, git_root)
	commit_msg = clean_commit_message(commit_msg)

	if commit_msg == "" then
		vim.notify("AI 返回了空的提交消息，请重试", vim.log.levels.WARN, { title = "ChatCommit" })
		return
	end

	-- 写入 .git/COMMIT_EDITMSG（git commit 时会自动读取）
	local path = git_root .. "/.git/COMMIT_EDITMSG"
	os.remove(path)
	local f = io.open(path, "w")
	if f then
		f:write(commit_msg)
		f:close()
	else
		vim.notify("无法写入 " .. path, vim.log.levels.ERROR, { title = "ChatCommit" })
		return
	end

	-- 复制到系统剪贴板
	vim.fn.setreg("+", commit_msg)

	-- 显示结果
	local lines = vim.split(commit_msg, "\n")
	local preview = lines[1] or commit_msg
	if #lines > 1 then
		preview = preview .. " ...（共 " .. #lines .. " 行）"
	end

	vim.notify(preview, vim.log.levels.INFO, {
		title = "ChatCommit ✓  已写入 .git/COMMIT_EDITMSG + 剪贴板",
		timeout = 8000,
	})
end

--- 入口：生成提交消息
function M.generate()
	local git_root = get_git_root()
	if not git_root then
		return
	end

	local staged_diff = get_staged_diff(git_root)
	if not staged_diff then
		return
	end

	local unstaged_diff = get_unstaged_diff(git_root)
	local prompt = build_prompt(staged_diff, unstaged_diff)

	vim.notify("正在请求 AI 生成提交消息…", vim.log.levels.INFO, { title = "ChatCommit" })

	api.query(prompt, function(response)
		if response then
			handle_commit_message(response, git_root)
		end
	end)
end

return M
