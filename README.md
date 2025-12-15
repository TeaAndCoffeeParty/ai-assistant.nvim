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
  - **引用文件夹中的.h/.cpp文件：** 将指定文件夹中的所有.h和.cpp文件内容作为上下文发送给AI。
- **会话历史管理：**
  - 保存和加载聊天会话历史，方便后续回顾。
  - 清除当前会话历史或清除发送给 AI 的上下文。
- **流式响应：** AI 回复以流式（逐字）方式显示，提供更流畅的用户体验。
- **高度可配置：** 灵活的配置选项，包括 API 密钥、模型选择、窗口布局等。

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
    -- apis = {
    --  google_gemini = {
    --    model = "gemini-2.5-pro",
    --  },
    --},
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
- `:ChatFolder [folder_path]`：将指定文件夹中的所有.h和.cpp文件内容作为上下文发送给AI（默认为当前文件夹）。
- `:ChatShowHistory`：显示所有聊天会话历史。
- `:ChatClearHistory`：清除所有已保存的聊天会话历史。
- `:ChatClearPrompt`：清除当前 AI 聊天输入框中的上下文信息，但不影响已发送的聊天历史。
- `:ChatClose`：关闭 AI 聊天窗口。
- `:ChatSelectModel`：弹出一个选择框，让你选择要使用的 AI 模型。
- `:ChatToggleWidth`： 切换聊天窗口的宽度（宽/窄）。

### 快捷键 (Keymaps)

**重要提示：本插件不再提供默认快捷键绑定。你需要手动配置你喜欢的快捷键来调用上述命令。**

以下是一些绑定快捷键的示例，你可以将其添加到你的 `init.lua` 或插件配置中（例如，在 `lazy.nvim` 的 `config` 函数里）：

```lua
  -- 示例：在普通模式下绑定快捷键
  vim.keymap.set('n', '<leader>cc', '<cmd>Chat<CR>', { desc = 'Open AI Chat Window' })
  vim.keymap.set('v', '<leader>cc', '<cmd>ChatVisual<CR>', { desc = 'Send Visual Selection to Chat' })

  -- 示例：发送代码上下文
  vim.keymap.set('n', '<leader>cl', '<cmd>ChatCurrentLine<CR>', { desc = 'Send Current Line to Chat' })
  vim.keymap.set('n', '<leader>cf', '<cmd>ChatFile<CR>', { desc = 'Send Entire File to Chat' })

  -- 示例：历史管理
  vim.keymap.set('n', '<leader>ch', '<cmd>ChatShowHistory<CR>', { desc = 'Show Chat History' })
  vim.keymap.set('n', '<leader>cH', '<cmd>ChatClearHistory<CR>', { desc = 'Clear All Chat History' }) -- 大写H表示清除所有
  vim.keymap.set('n', '<leader>cp', '<cmd>ChatClearPrompt<CR>', { desc = 'Clear Chat Prompt Context' })

  -- 示例：模型选择
  vim.keymap.set('n', '<leader>cs', '<cmd>ChatSelectModel<CR>', { desc = 'Select AI Model' })

  -- 聊天输入窗口中的提交消息快捷键 (此快捷键由插件UI内部处理，无需额外绑定)
  -- 默认是 <C-Enter>，用于在聊天输入框中发送消息
```

**关于 `which-key.nvim` 集成：**

如果你使用 `which-key.nvim`，你可以在绑定快捷键的同时，为它们注册描述和图标，以获得更好的视觉提示。例如：

```lua
  -- 示例 which-key.nvim 配置 (假设你已经安装并配置了 which-key)
  local wk = require('which-key')
  wk.add({
    -- ai-assistant
    { "<leader>a", group = "AI Assistant", icon = "🤖 " },
    { "<leader>ao", ":Chat<CR>", desc = "Open Chat", icon = "💬 ", mode = "n" },
    { "<leader>al", ":ChatCurrentLine<CR>", desc = "Send Current Line", icon = "📎 ", mode = "n" },
    { "<leader>af", ":ChatFile<CR>", desc = "Send Entire File", icon = "📁 ", mode = "n" },
    { "<leader>ah", ":ChatShowHistory<CR>", desc = "Show History", icon = "📜 ", mode = "n" },
    { "<leader>ac", ":ChatClearHistory<CR>", desc = "Clear History", icon = "🗑 ", mode = "n" },
    { "<leader>ap", ":ChatClearPrompt<CR>", desc = "Clear Prompt Context", icon = "🧹 ", mode = "n" },
    { "<leader>am", ":ChatSelectModel<CR>", desc = "Select AI Model", icon = "🧠 ", mode = "n" },
    -- Visual 模式
    { "<leader>av", ":ChatVisual<CR>", desc = "Send Visual Selection", icon = "🔍 ", mode = "v" },
  })
```

### 聊天交互

1. **打开聊天窗口：** 使用你配置的快捷键（例如 `<leader>ao`）或 `:Chat` 命令。
2. **输入消息：** 在底部的输入框中输入你的问题或指令。
   - 如果你使用了引用代码功能，输入框会预填充一个 Markdown 代码块。你可以在代码块下方输入你的具体问题。
3. **发送消息：** 在输入框中按下 `submit` 快捷键 (`<C-Enter>`)。
4. **关闭窗口：** 在聊天窗口中按下 `ESC` 或配置的关闭快捷键。

## 🤝 贡献

欢迎任何形式的贡献！如果你有任何功能建议、Bug 报告或代码改进，请随时提交 Pull Request 或 Issue。

[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/TeaAndCoffeeParty/ai-assistant.nvim)

## 📜 许可证

本项目采用 [MIT 许可证](LICENSE)。
