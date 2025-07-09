# deepseek.nvim

## lazy vim example

```lua
-- DeepSeek plugin example

return {
  "TeaAndCoffeeParty/deepseek.nvim",
  opts = {
    enabled = true,
    window = { width = 100, height = 40, split_ratio = 0.2 },
    api_key = os.getenv("DEEPSEEK_API_KEY"),
    model = "deepseek-chat",
    timeout = 60000,
  },
  dependencies = {
    "nvim-lua/plenary.nvim",
  },
  config = function(_, opts)
    require("deepseek").setup(opts)
  end,
}
```

