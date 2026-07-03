local M = {}

local config = require("ai-assistant.config")

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

--- 清理 AI 回复：去除代码围栏标记、压缩连续空行、去除首尾空行
---@param raw string
---@return string
local function clean_commit_message(raw)
	-- 去除开头的代码围栏标记
	local msg = raw:gsub("^```[^\n]*\n", "")
	-- 去除结尾的代码围栏标记
	msg = msg:gsub("\n```%s*$", "")

	-- 按行拆分，逐行处理空行
	local lines = vim.split(msg, "\n")

	-- 找到第一个非空行和最后一个非空行，裁剪首尾空行
	local first, last = 1, #lines
	while first <= #lines and lines[first]:match("^%s*$") do
		first = first + 1
	end
	while last >= first and lines[last]:match("^%s*$") do
		last = last - 1
	end

	-- 重建行列表，压缩连续空行为单个空行
	local cleaned = {}
	local prev_empty = false
	for i = first, last do
		local is_empty = lines[i]:match("^%s*$") ~= nil
		if is_empty then
			if not prev_empty then
				table.insert(cleaned, "")
				prev_empty = true
			end
			-- 连续空行：跳过
		else
			table.insert(cleaned, lines[i])
			prev_empty = false
		end
	end

	return table.concat(cleaned, "\n")
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

--- 异步调用 AI API（用 vim.fn.jobstart 避免阻塞 UI）
---@param messages table 消息列表
---@param callbacks {on_finish: fun(response:string), on_error: fun(msg:string)}
local function query_async(messages, callbacks)
	local model_config, err = config.get_model()

	if err or not model_config then
		vim.schedule(function()
			callbacks.on_error("获取模型配置失败: " .. (err or "未知错误"))
		end)
		return
	end
	if not model_config.api_key then
		vim.schedule(function()
			callbacks.on_error("API Key 未设置: " .. tostring(model_config.model))
		end)
		return
	end

	local body = {
		model = model_config.model,
		messages = messages,
		temperature = 0.3, -- 提交消息用较低温度，更稳定
		stream = false,
	}

	-- DeepSeek thinking 等扩展字段
	if model_config.thinking_enabled == true then
		body.thinking = vim.deepcopy(model_config.thinking or { type = "enabled" })
		if model_config.reasoning_effort then
			body.reasoning_effort = model_config.reasoning_effort
		end
	end

	local payload = vim.json.encode(body)

	local cmd = {
		"curl",
		"-sS", -- -S: 出错时显示错误信息
		"--no-buffer",
		"-X",
		"POST",
		"-H",
		"Content-Type: application/json",
		"-H",
		"Authorization: Bearer " .. model_config.api_key,
		"--write-out",
		"HTTP_STATUS:%{http_code}",
		"--data",
		payload,
		model_config.api_url,
	}

	local stdout_lines = {}
	local stderr_lines = {}
	local http_code = nil
	local finished = false

	local function finish_with_error(msg)
		if finished then
			return
		end
		finished = true
		vim.schedule(function()
			callbacks.on_error(msg)
		end)
	end

	local function finish_with_success(body_str)
		if finished then
			return
		end
		finished = true
		vim.schedule(function()
			callbacks.on_finish(body_str)
		end)
	end

	vim.fn.jobstart(cmd, {
		stdout_buffered = false,
		on_stderr = function(_, data, _)
			for _, line in ipairs(data) do
				if line ~= "" then
					table.insert(stderr_lines, line)
				end
			end
		end,
		on_stdout = function(_, data, _)
			for _, line in ipairs(data) do
				-- 捕获 write-out 状态码
				if line:find("HTTP_STATUS:") then
					local code_str = line:match("HTTP_STATUS:(%d+)")
					if code_str then
						http_code = tonumber(code_str)
					end
				else
					table.insert(stdout_lines, line)
				end
			end
		end,
		on_exit = function(_, code, signal)
			if code ~= 0 then
				local err = "curl 退出码 " .. tostring(code)
				if signal ~= 0 then
					err = err .. ", 信号 " .. tostring(signal)
				end
				if #stderr_lines > 0 then
					err = err .. ": " .. table.concat(stderr_lines, " ")
				end
				finish_with_error(err)
				return
			end

			local body_str = table.concat(stdout_lines, "\n")

			-- curl 即使 HTTP 错误也返回 0，必须检查 write-out 状态码
			if http_code and http_code ~= 200 then
				-- 尝试解析错误详情
				local err_detail = ""
				local ok, parsed = pcall(vim.json.decode, body_str)
				if ok and parsed and parsed.error then
					err_detail = " - " .. tostring(parsed.error.message or parsed.error)
				end
				finish_with_error(string.format("API HTTP %d%s", http_code, err_detail))
				return
			end

			if body_str == "" then
				finish_with_error("API 返回了空响应")
				return
			end

			-- 解析 JSON 响应
			local ok, result = pcall(vim.json.decode, body_str)
			if not ok or not result.choices or not result.choices[1] then
				finish_with_error("无法解析 API 响应: " .. body_str:sub(1, 200))
				return
			end

			local content = result.choices[1].message.content
			if not content or content == "" then
				finish_with_error("API 返回的消息内容为空")
				return
			end

			finish_with_success(content)
		end,
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

	query_async({
		{ role = "user", content = prompt },
	}, {
		on_finish = function(response)
			handle_commit_message(response, git_root)
		end,
		on_error = function(err_msg)
			vim.notify("ChatCommit 失败: " .. err_msg, vim.log.levels.ERROR, { title = "ChatCommit" })
		end,
	})
end

return M
