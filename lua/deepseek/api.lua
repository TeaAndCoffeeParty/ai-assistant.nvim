local curl = require("plenary.curl")
local json = vim.json

local api = {}
local default_timeout = 60000

function api.query(prompt, callback)
	local model = require("deepseek").config.get_model

	if not model.api_key then
		vim.notify("Chat API Key Not Found", vim.log.levels.ERROR)
		return
	end

	local request_data = {
		model = model.model or "deepseek-chat",
		messages = {
			{
				role = "user",
				content = prompt,
			},
		},
		temperature = 0.7,
		stream = false,
	}

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
	local model_config, err = require("deepseek.config").get_model()

	if err or not model_config then
		callbacks.on_error("Failed to get model config: " .. (err or "Unknown error"))
		return
	end
	if not model_config or not model_config.api_key then
		callbacks.on_error("API Key not set for model: " .. model_config.model)
		return
	end

	local payload = vim.json.encode({
		model = model_config.model,
		messages = messages,
		temperature = 0.7,
		max_tokens = 1000, -- 限制 AI 回复的长度
		stream = true, -- 开启流式传输
	})

	-- 调试信息
	-- print("Starting stream request to:", model.api_url)

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

	local full_response = ""
	local job_id = vim.fn.jobstart(cmd, {
		stdout_buffered = false,
		on_stdout = function(_, data, _)
			for _, line in ipairs(data) do
				if line:find("^data: ") then
					local chunk = line:sub(6)
					if chunk == "[DONE]" then
						print("Received DONE signal") -- 调试
						vim.schedule(callbacks.on_finish)
					else
						local ok, json_data = pcall(vim.json.decode, chunk)
						if ok and json_data.choices then
							callbacks.on_data(json_data.choices[1].delta.content or "")
						end
					end
				elseif line:find("HTTP_STATUS:") then
					print("HTTP Status:", line) --调试状态码
				end
			end
		end,
		on_exit = function(_, code, signal)
			print("Job exited. Code:", code, "Signal:", signal) -- 关键调试信息
			vim.schedule(function()
				if code == 0 then
					callbacks.on_finish()
				else
					callbacks.on_error("curl exited with code " .. code)
				end
			end)
		end,
	})

	-- 超时保险
	vim.defer_fn(function()
		if vim.fn.jobwait({ job_id }, 0)[1] == -1 then
			print("Force stopping job due to timeout")
			vim.fn.jobstop(job_id)
			callbacks.on_error("Reqest timeout")
		end
	end, model_config.timeout or default_timeout)
end

return api
