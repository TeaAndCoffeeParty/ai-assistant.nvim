local curl = require("plenary.curl")
local json = require("cjson")

local api = {}

function api.query(prompt, callback)
	local config = require("deepseek").config.config

	print(vim.inspect(config))

	local data = {
		model = config.model,
		message = {
			{ role = "user", content = prompt },
		},
		temperature = 0.7,
	}

	curl.request({
		url = config.api_url,
		moethod = "POST",
		headers = {
			["Content-Type"] = "application/json",
			["Authorization"] = "Bearer " .. config.api_key,
		},
		body = json.encode(data),
		timeout = config.timeout,
		callback = function(response)
			if response.status ~= 200 then
				local err = json.decode(response.body).error or "未知错误"
				vim.schedule(function()
					vim.notify("API 错误： " .. err.message, vim.log.levels.ERROR)
				end)
				return
			end

			local result = json.decode(response.body)
			vim.schedule(function()
				callback(result.choices[1].message.content)
			end)
		end,
	})
end

return api
