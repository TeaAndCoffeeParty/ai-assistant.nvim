local curl = require("plenary.curl")
local json = vim.json

local api = {}

function api.query(prompt, callback)
	local config = require("deepseek").config or {}

	if not config.api_key then
		vim.notify("DeepSeek API key 未配置", vim.log.levels.ERROR)
		return
	end

	local request_data = {
		model = config.model or "deepseek-chat",
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
		url = config.api_url or "https://api.deepseek.com/v1/chat/completions",
		method = "POST",
		headers = {
			["Content-Type"] = "application/json",
			["Authorization"] = "Bearer " .. config.api_key,
		},
		body = json.encode(request_data),
		timeout = config.timeout or 30000,
	})

	-- 错误处理
	if not ok then
		vim.notify("API 请求失败" .. tostring(response), vim.log.levels.ERROR)
	end

	-- 检查HTTP状态
	if response.status ~= 200 then
		local err_msg = "API 错误：HTTP " .. tostring(response.status)
		if response.body then
			local parse_ok, err_data = pcall(json.decode, response.body)
			if parse_ok and err_data and err_data.error then
				err_msg = err_msg .. " - " .. tostring(err_data.error.message)
			else
				err_msg = err_msg .. "\n响应体：" .. tostring(response.body)
			end
		end
		vim.notify(err_msg, vim.log.levels.ERROR)
		return
	end

	-- 解析响应
	local decode_ok, result = pcall(json.decode, response.body)
	if not decode_ok or not result.choices then
		vim.notify("无效的 API 响应格式：\n" .. tostring(response.body), vim.log.levels.ERROR)
		return
	end

	callback(result.choices[1].message.content)
end

return api
