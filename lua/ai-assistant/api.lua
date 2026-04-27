local curl = require("plenary.curl")
local json = vim.json

local api = {}
local default_timeout = 60000

--- 将 SSE 里 choices[].delta 拆成正文与思考链（分开回调，便于 UI 区分）
local function stream_delta_parts(delta)
	if type(delta) ~= "table" then
		return "", ""
	end
	local c = delta.content
	local content_str = ""
	if type(c) == "string" then
		content_str = c
	elseif type(c) == "table" then
		local parts = {}
		if #c > 0 then
			for _, part in ipairs(c) do
				if type(part) == "table" and type(part.text) == "string" then
					table.insert(parts, part.text)
				elseif type(part) == "string" then
					table.insert(parts, part)
				end
			end
		elseif type(c.text) == "string" then
			table.insert(parts, c.text)
		end
		content_str = table.concat(parts)
	elseif type(c) == "number" or type(c) == "boolean" then
		content_str = tostring(c)
	end

	local thinking_str = ""
	for _, key in ipairs({ "reasoning_content", "reasoning", "thinking" }) do
		local v = delta[key]
		if type(v) == "string" and v ~= "" then
			thinking_str = v
			break
		end
	end
	return content_str, thinking_str
end

--- 仅当配置显式开启时附加（当前仅 DeepSeek 文档中的 thinking / reasoning_effort）
---@param body table 将编码为 JSON 的请求体
---@param model_config table
local function apply_thinking_fields(body, model_config)
	if model_config.thinking_enabled == true then
		body.thinking = vim.tbl_extend("force", {}, model_config.thinking or { type = "enabled" })
		if model_config.reasoning_effort then
			body.reasoning_effort = model_config.reasoning_effort
		end
	end
end

function api.query(prompt, callback)
	local model, gerr = require("ai-assistant.config").get_model()
	if gerr or not model then
		vim.notify("Chat API config: " .. tostring(gerr or "nil"), vim.log.levels.ERROR)
		return
	end

	if not model.api_key then
		vim.notify("Chat API Key Not Found", vim.log.levels.ERROR)
		return
	end

	local request_data = {
		model = model.model or "deepseek-v4-flash",
		messages = {
			{
				role = "user",
				content = prompt,
			},
		},
		temperature = 0.7,
		stream = false,
	}
	apply_thinking_fields(request_data, model)

	local ok, response = pcall(curl.request, {
		url = model.api_url or "https://api.deepseek.com/v1/chat/completions",
		method = "POST",
		headers = {
			["Content-Type"] = "application/json",
			["Authorization"] = "Bearer " .. model.api_key,
		},
		body = json.encode(request_data),
		timeout = model.timeout or default_timeout,
	})

	-- 错误处理
	if not ok then
		vim.notify("API Request Failed:" .. tostring(response), vim.log.levels.ERROR)
	end

	-- 检查HTTP状态
	if response.status ~= 200 then
		local err_msg = "API Error: HTTP " .. tostring(response.status)
		if response.body then
			local parse_ok, err_data = pcall(json.decode, response.body)
			if parse_ok and err_data and err_data.error then
				err_msg = err_msg .. " - " .. tostring(err_data.error.message)
			else
				err_msg = err_msg .. "\nResponse：" .. tostring(response.body)
			end
		end
		vim.notify(err_msg, vim.log.levels.ERROR)
		return
	end

	-- 解析响应
	local decode_ok, result = pcall(json.decode, response.body)
	if not decode_ok or not result.choices then
		vim.notify("Invalid API Response：\n" .. tostring(response.body), vim.log.levels.ERROR)
		return
	end

	callback(result.choices[1].message.content)
end

function api.query_stream(messages, callbacks)
	local model_config, err = require("ai-assistant.config").get_model()

	if err or not model_config then
		callbacks.on_error("Failed to get model config: " .. (err or "Unknown error"))
		return
	end
	if not model_config or not model_config.api_key then
		callbacks.on_error("API Key not set for model: " .. model_config.model)
		return
	end

	local body = {
		model = model_config.model,
		messages = messages,
		temperature = 0.7,
		stream = true,
	}
	apply_thinking_fields(body, model_config)
	local payload = vim.json.encode(body)

	local prov = require("ai-assistant.config").config.select_model or "?"
	vim.notify(string.format("请求 [%s] 模型 %s …", prov, model_config.model), vim.log.levels.INFO)

	local cmd = {
		"curl",
		"-sN",
		"--no-buffer",
		"-X",
		"POST",
		"-H",
		"Content-Type: application/json",
		"-H",
		"Authorization: Bearer " .. model_config.api_key,
		"-H",
		"Accept: text/event-stream",
		"-H",
		"Connection: keep-alive",
		"--write-out",
		"HTTP_STATUS:%{http_code}",
		"--data",
		payload,
		model_config.api_url,
	}

	local http_code ---@type integer|nil
	local stream_error ---@type string|nil
	local finish_scheduled = false
	local stderr_lines = {}

	local function schedule_finish_once()
		if finish_scheduled then
			return
		end
		finish_scheduled = true
		vim.schedule(callbacks.on_finish)
	end

	local function schedule_error_once(msg)
		if finish_scheduled then
			return
		end
		finish_scheduled = true
		vim.schedule(function()
			callbacks.on_error(msg)
		end)
	end

	local job_id = vim.fn.jobstart(cmd, {
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
				line = line:gsub("\r$", "")
				if line:find("^data: ") then
					local chunk = line:sub(7):match("^%s*(.*)$") or line:sub(7)
					if chunk == "[DONE]" then
						-- 真正结束与 HTTP 校验在 on_exit，避免 curl 退出 0 但 HTTP 4xx/5xx 时仍当作成功
					else
						local ok, json_data = pcall(vim.json.decode, chunk)
						if ok and json_data.choices then
							local delta = json_data.choices[1].delta
							local content_str, thinking_str = stream_delta_parts(delta)
							if thinking_str ~= "" then
								callbacks.on_data(thinking_str, "thinking")
							end
							if content_str ~= "" then
								callbacks.on_data(content_str, "content")
							end
						elseif ok and json_data.error then
							local e = json_data.error
							if type(e) == "table" and e.message then
								stream_error = tostring(e.message)
							else
								stream_error = vim.json.encode(json_data.error)
							end
						end
					end
				elseif line:find("HTTP_STATUS:") then
					local code_str = line:match("HTTP_STATUS:(%d+)")
					if code_str then
						http_code = tonumber(code_str)
					end
				end
			end
		end,
		on_exit = function(_, code, signal)
			vim.schedule(function()
				if finish_scheduled then
					return
				end
				if code ~= 0 then
					local err = "curl exited with code " .. tostring(code)
					if signal ~= 0 then
						err = err .. ", signal " .. tostring(signal)
					end
					if #stderr_lines > 0 then
						err = err .. ": " .. table.concat(stderr_lines, " ")
					end
					schedule_error_once(err)
					return
				end
				-- curl 对 HTTP 错误默认仍返回 0，必须看 write-out 里的状态码
				if stream_error then
					schedule_error_once(stream_error)
					return
				end
				if http_code and http_code ~= 200 then
					schedule_error_once(
						string.format(
							"API HTTP %s（curl 仍为 0）。请检查 api_url、API Key、模型名与额度。",
							tostring(http_code)
						)
					)
					return
				end
				schedule_finish_once()
			end)
		end,
	})

	-- 超时保险
	vim.defer_fn(function()
		if vim.fn.jobwait({ job_id }, 0)[1] == -1 then
			vim.fn.jobstop(job_id)
			schedule_error_once("Request timeout")
		end
	end, model_config.timeout or default_timeout)
end

return api
