# 🚀 AI-assistant.nvim - 智能 AI 聊天与代码助手

`ai-assistant.nvim` 是一个功能丰富的 Neovim 插件，它集成了强大的 AI 聊天功能，并允许你将代码内容作为上下文发送给 AI，从而获得更精准、更实用的编程协助。

## ✨ 功能特性

- **多模型支持：** 轻松配置和切换 Google Gemini、阿里云通义千问 (Qwen)、Deepseek 等多种主流 AI 模型。
- **交互式聊天界面：** 提供一个简洁的浮动窗口，用于与 AI 进行实时对话。
- **代码上下文引用：**
  - **引用当前行：** 快速将光标所在行代码作为上下文发送。
  - **引用可视选择：** 在 Visual 模式下选择代码块，并将其作为上下文发送。
  - **引用整个文件：** 将当前编辑的整个文件内容（支持智能截断）发送给 AI。
  - **引用指定行范围：** 精确指定文件中的行号范围作为上下文。
- **会话历史管理：**
  - 保存和加载聊天会话历史，方便后续回顾。
  - 清除当前会话历史或清除发送给 AI 的上下文。
- **流式响应：** AI 回复以流式（逐字）方式显示，提供更流畅的用户体验。
- **高度可配置：** 灵活的配置选项，包括 API 密钥、模型选择、窗口布局、快捷键等。

## 📦 安装

使用你喜欢的 Neovim 插件管理器进行安装。

**使用 `lazy.nvim` (推荐):**

```lua
-- init.lua 或 plugins/ai-assistant.lua

return {
  "TeaAndCoffeeParty/ai-assistant.nvim",
  opts = {
    enabled = true,
    window = { width = 0.6, height = 0.8, split_ratio = 0.2 },
    select_model = "google_gemini", -- model list "google_gemini", "aliyun_qwen", "deepseek"
    timeout = 80000,
    -- max_context_lines = 500, -- 引用整个文件时最大行数
    -- max_prompt_tokens = 5000, -- 预警token个数
    -- max_prompt_token_ratio = 2, -- English:3.5, Chines 2 or 2.5
  },
  dependencies = {
    "nvim-lua/plenary.nvim",
  },
  config = function(_, opts)
    require("ai-assistant").setup(opts)
  end,
}
```

**使用 `packer.nvim`:**

```lua
-- plugins.lua
use {
  "TeaAndCoffeeParty/ai-assistant.nvim",
  requires = {
    'nvim-lua/plenary.nvim',
  },
  config = function()
    require('ai-assistant').setup({
      -- 你的配置选项
    })
  end,
}
```

## ⚙️ 配置

插件提供了丰富的配置选项，你可以根据自己的需求在 `setup()` 函数中进行配置。

```lua
require('ai-assistant').setup({
  enabled = true, -- 是否启用插件，默认为 true

  -- 窗口布局配置
  window = {
    width = 0.6,         -- 聊天窗口宽度占屏幕宽度的比例 (0.0 - 1.0)
    height = 0.8,        -- 聊天窗口高度占屏幕高度的比例 (0.0 - 1.0)
    split_ratio = 0.2,   -- 输入窗口高度占总窗口高度的比例 (0.0 - 1.0)
  },

  -- 快捷键配置
  keymaps = {
    open_chat = "<leader>dc",         -- 打开 AI 聊天窗口 (或发送 Visual 选中内容)
    submit = "<C-Enter>",             -- 在输入窗口中提交消息
    show_history = "<leader>dh",      -- 显示聊天历史窗口
    clear_history = "<leader>ddh",    -- 清除所有聊天历史
    clear_prompt = "<leader>ddp",     -- 清除当前发送给 AI 的上下文（不是聊天历史）
    chat_current_line = "<leader>drl",-- 引用当前行代码并打开聊天
    chat_file = "<leader>drf",        -- 引用整个文件代码并打开聊天
    -- 引用指定行范围目前通过命令 `:ChatRange <start> <end>` 使用
  },

  -- AI API 配置
  apis = {
    google_gemini = {
      api_url = "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions",
      api_key = os.getenv("GEMINI_API_KEY"), -- 推荐使用环境变量
      model = "gemini-2.5-flash",
    },
    aliyun_qwen = {
      api_url = "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions",
      api_key = os.getenv("DASHSCOPE_API_KEY"),
      model = "qwen-plus",
    },
    deepseek = {
      api_url = "https://api.deepseek.com/v1/chat/completions",
      api_key = os.getenv("DEEPSEEK_API_KEY"),
      model = "deepseek-chat",
    },
  },
  select_model = "google_gemini", -- 默认选用的 AI 模型 (对应 apis 中的键)

  -- 历史记录配置
  history = {
    max_save_count = 20, -- 最多保存的聊天会话数量
    chat_max_count = 10, -- 发送给 AI 的历史消息数量 (每轮对话)
  },

  max_context_lines = 1000, -- 引用整个文件时，最大允许的上下文行数，超出部分将被截断
})
```

### 环境变量设置

为了保护你的 API 密钥，强烈建议通过环境变量设置它们：

```bash
# 在你的 shell 配置文件中 (如 ~/.bashrc, ~/.zshrc, ~/.config/fish/config.fish)
export GEMINI_API_KEY="your_gemini_api_key_here"
export DASHSCOPE_API_KEY="your_dashscope_api_key_here"
export DEEPSEEK_API_KEY="your_deepseek_api_key_here"

# 刷新你的 shell 配置
source ~/.zshrc # 或你的相应文件
```

## 🚀 使用方法

### 命令 (Commands)

- `:Chat`：打开 AI 聊天窗口。
- `:ChatCurrentLine`：将光标所在行代码作为上下文发送，并打开聊天窗口。
- `:ChatVisual`：在 Visual 模式下，将选中的代码作为上下文发送，并打开聊天窗口。
- `:ChatFile`：将当前文件所有代码（可能截断）作为上下文发送，并打开聊天窗口。
- `:ChatRange <start_line> <end_line>`：将当前文件指定行范围的代码作为上下文发送，并打开聊天窗口。
  - 例如：`:ChatRange 10 50`
- `:ChatShowHistory`：显示所有聊天会话历史。
- `:ChatClearHistory`：清除所有已保存的聊天会话历史。
- `:ChatClearPrompt`：清除当前 AI 聊天输入框中的上下文信息，但不影响已发送的聊天历史。
- `:ChatSelectModel`：弹出一个选择框，让你选择要使用的 AI 模型。

### 快捷键 (Keymaps)

插件默认提供以下快捷键（可在配置中修改）：

| 模式     | 快捷键 (默认) | 命令                    | 描述                                       |
| :------- | :------------ | :---------------------- | :----------------------------------------- |
| `n`, `v` | `<leader>dc`  | `:Chat` / `:ChatVisual` | `n`：打开聊天窗口；`v`：发送选中内容并打开 |
| `i`      | `<C-Enter>`   | 提交消息                | 在聊天输入窗口中发送消息                   |
| `n`      | `<leader>dh`  | `:ChatShowHistory`      | 显示聊天历史                               |
| `n`      | `<leader>ddh` | `:ChatClearHistory`     | 清除所有聊天历史                           |
| `n`      | `<leader>ddp` | `:ChatClearPrompt`      | 清除当前聊天输入框的上下文                 |
| `n`      | `<leader>drl` | `:ChatCurrentLine`      | 引用当前行代码并打开聊天                   |
| `n`      | `<leader>drf` | `:ChatFile`             | 引用整个文件代码并打开聊天                 |
| `n`      | `<leader>ds`  | `:ChatSelectModel`      | 选择当前使用的 AI 模型                     |

### 聊天交互

1. **打开聊天窗口：** 使用 `:Chat` 命令或 `open_chat` 快捷键。
2. **输入消息：** 在底部的输入框中输入你的问题或指令。
   - 如果你使用了引用代码功能，输入框会预填充一个 Markdown 代码块。你可以在代码块下方输入你的具体问题。
3. **发送消息：** 在输入框中按下 `submit` 快捷键 (`<C-Enter>`)。
4. **关闭窗口：** 在聊天窗口中按下 `ESC` 或配置的关闭快捷键。

## 🤝 贡献

欢迎任何形式的贡献！如果你有任何功能建议、Bug 报告或代码改进，请随时提交 Pull Request 或 Issue。

## 📜 许可证

本项目采用 [MIT 许可证](LICENSE)。
