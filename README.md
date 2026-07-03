# AI-assistant.nvim

Neovim 插件：多模型 AI 对话、代码上下文、流式回复、可选 C++ 代码地图（clangd）以降低 token；支持会话历史与模型选择持久化。

## 功能概览

- **多模型**：在 `setup` 的 `apis` 中配置多个厂商（如 Google Gemini、阿里云 Qwen、DeepSeek、Moonshot、ModelScope 等），用 `:ChatSelectModel` 切换。
- **聊天界面**
  - **侧栏模式**（默认）：右侧固定列宽分栏，类似 IDE 侧栏，便于 `Ctrl-w h` / `Ctrl-w l` 与编辑区切换。
  - **浮动模式**：居中靠右双浮动窗；通过 `window.layout = "float"` 启用。
- **代码上下文**：当前行、Visual 选区、整文件（可截断）、行范围、文件夹内 `.h/.cpp` 批量引用。
- **流式输出**：SSE 流式显示；HTTP 非 200 会报错；支持将 **Thinking** 与 **Answer** 分区展示（Markdown 标题 + 引用块）。
- **DeepSeek**：默认使用 [官方文档](https://api-docs.deepseek.com/zh-cn/) 推荐的新模型名（如 `deepseek-v4-flash`）；可选 **thinking** 请求体（仅对配置了 `supports_thinking` 的 provider 生效，默认仅 DeepSeek）。
- **C++ 代码地图**（可选）：基于 **clangd** 拉取符号与调用关系，生成摘要；分析/优化类问题可自动附带地图以减少整文件 token（`:AIMapGenerate`）。
- **历史与上下文**：磁盘保存历史；`:ChatClearPrompt` 清空「发给 API 的上下文」；切换模型时可自动重置上下文，避免混用人设。
- **模型选择持久化**：写入 `stdpath("data")/ai-assistant-selection.json`，下次启动恢复（可关闭）。

## 安装

**lazy.nvim 示例：**

```lua
{
  "TeaAndCoffeeParty/ai-assistant.nvim", -- 或你的 fork / 本地路径
  dependencies = { "nvim-lua/plenary.nvim" },
  opts = {
    enabled = true,
    select_model = "deepseek",
    window = {
      layout = "split",       -- "split" | "float"
      sidebar_width = 80,   -- split 下列宽
      width = 0.6,          -- float 时宽度比例
      height = 0.8,
      split_ratio = 0.22,   -- 底部输入区高度占比
    },
    map = {
      enabled = true,
      attach_on_keywords = true, -- false 时只要已有地图缓存就尝试附带
      max_files = 120,
    },
  },
  config = function(_, opts)
    require("ai-assistant").setup(opts)
  end,
}
```

**依赖**：`plenary.nvim`（非流式请求等）。

## 配置说明

```lua
require("ai-assistant").setup({
  enabled = true,

  window = {
    layout = "split",        -- 默认右侧分栏；"float" 为浮动窗
    sidebar_width = 80,      -- split 时侧栏宽度（列）
    width = 0.6,             -- float 时占屏宽比例
    height = 0.8,
    split_ratio = 0.22,      -- 输入区占侧栏高度比例
  },

  apis = {
    deepseek = {
      api_url = "https://api.deepseek.com/v1/chat/completions",
      api_key = os.getenv("DEEPSEEK_API_KEY"),
      model = "deepseek-v4-flash",
      -- 仅 DeepSeek 官方扩展字段；其它厂商不要照抄
      supports_thinking = true,
      thinking_enabled = false,       -- true 时请求体带 thinking + reasoning_effort
      thinking = { type = "enabled" },
      reasoning_effort = "medium",    -- "low" | "medium" | "high"
    },
    -- google_gemini、aliyun_qwen、moonshot、modelscope … 见 lua/ai-assistant/config.lua 默认值
  },
  select_model = "deepseek",

  history = {
    max_save_count = 20,
    chat_max_count = 10,
    -- 为 true：每次启动加载历史后清空「发给 API 的上下文」，避免换模型后人设被旧对话带偏
    isolate_context_after_load = false,
  },

  map = {
    enabled = true,
    attach_on_keywords = true,
    max_files = 120,
    max_call_symbols_per_file = 24,
    include_incoming = true,
    max_incoming_per_symbol = 8,
    cross_file = true,
  },

  max_context_lines = 1000,
  max_prompt_tokens = 5000,
  max_prompt_token_ratio = 2,
  persist_selection = true, -- false 则不读写模型选择缓存文件
})
```

### 环境变量（示例）

```bash
export GEMINI_API_KEY="..."
export DASHSCOPE_API_KEY="..."
export DEEPSEEK_API_KEY="..."
export MOONSHOT_API_KEY="..."
export MODELSCOPE_API_KEY="..."
```

### 持久化文件路径

| 用途 | 路径 |
|------|------|
| 模型与 provider 选择 | `stdpath("data")/ai-assistant-selection.json` |
| 聊天历史 | `stdpath("data")/ai_chat_history.json` |
| C++ 代码地图缓存 | `stdpath("data")/ai-assistant-cpp-map.json` |

## 命令一览

| 命令 | 说明 |
|------|------|
| `:Chat` | 打开聊天窗口 |
| `:ChatClose` | 关闭聊天窗口 |
| `:ChatCurrentLine` | 当前行作为上下文并打开聊天 |
| `:ChatVisual` | Visual 选区作为上下文 |
| `:ChatFile` | 当前整文件（可截断） |
| `:ChatRange <start> <end>` | 当前文件行范围 |
| `:ChatFolder [path]` | 文件夹内 `.h/.cpp` |
| `:ChatShowHistory` | 查看历史 |
| `:ChatClearHistory` | 清空已保存历史 |
| `:ChatClearPrompt` | 清空「后续发给 API 的上下文指针」（本地历史仍可查看） |
| `:ChatSelectModel` | 选择 provider 与模型；成功后会写入选择缓存，并在切换 provider/模型时尝试重置 API 上下文 |
| `:ChatToggleWidth` | 侧栏：常规列宽 ↔ 约 95% 屏宽；浮动：配置比例 ↔ 95% |
| `:ChatToggleThinking` | 仅当当前 `apis` 项带 `supports_thinking` 时切换 `thinking_enabled`（默认仅 DeepSeek） |
| `:ChatCommit` | 获取 git 暂存区 diff，调用 AI 生成 conventional commits 提交消息，写入 COMMIT_EDITMSG + 剪贴板 |
| `:AIMapGenerate` | 生成/刷新 C++ 代码地图（需 clangd、`compile_commands.json`） |
| `:AIMapClear` | 删除地图内存与磁盘缓存 |
| `:AIMapStatus` | 当前项目根下是否有有效地图缓存 |

## 聊天操作说明

1. `:Chat` 打开窗口；侧栏模式下用 `Ctrl-w h` 回到代码，`Ctrl-w l` 回到侧栏。
2. 在底部输入区输入问题；若带代码块引用，可在块下用 `My question is:` 或直接写问题（见 `window.lua` 解析逻辑）。
3. **提交**：输入区默认 `<CR>` 提交；`<S-CR>` / `<C-j>` 插入换行。
4. **关闭**：输入/输出区 `Esc` 或 `q`。

## C++ 代码地图（省 token）

1. 工程已配置 **clangd** 与 **compile_commands.json**，并在项目内打开过 C++ 使 LSP 索引就绪。
2. 执行 `:AIMapGenerate`（大项目可能较慢）。
3. 若 `map.attach_on_keywords = true`，当用户问题命中「分析 / 优化 / refactor」等关键词时，会在**发给 API 的最后一条 user** 前自动拼接地图摘要；**聊天历史里仍保存你输入的原文**。
4. 不需要地图时设 `map.enabled = false`，或 `:AIMapClear`。

实现位于 `lua/ai-assistant/map/init.lua` 与 `lua/ai-assistant/map/cpp.lua`；对话侧关键词与拼装见 `lua/ai-assistant/chat.lua`。

## DeepSeek 与 Thinking

- 模型与 URL 以 [DeepSeek API 文档](https://api-docs.deepseek.com/zh-cn/) 为准；默认 `deepseek-v4-flash` 等。
- **Thinking 不会发给其它厂商**：仅当 `thinking_enabled == true` 且该 provider 配置了 `supports_thinking` 时，才会在 JSON 中加入 `thinking`、`reasoning_effort`。
- 运行时可用 `:ChatToggleThinking` 开关（需当前选中的是带 `supports_thinking` 的 provider）。

## 快捷键

插件**不**绑定默认快捷键，请自行映射上述命令，例如：

```lua
vim.keymap.set("n", "<leader>cc", "<cmd>Chat<CR>", { desc = "AI Chat" })
vim.keymap.set("v", "<leader>cc", "<cmd>ChatVisual<CR>", { desc = "AI Chat (visual)" })
```

## 贡献与许可证

欢迎 Issue / PR。

[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/TeaAndCoffeeParty/ai-assistant.nvim)

本项目采用 [MIT 许可证](LICENSE)。
