---
name: CREATE_OPENCLAW_JSON
description: 渲染 openclaw.json（LLM/agent 列表、SKILL 注册、MCP、沙箱、executionContract）。输入是 YAML，本文件输出仍是 JSON
version: "1.0"
tools:
  - mc
---

# CREATE_OPENCLAW_JSON

把 OPT 配置渲染成 openclaw 运行时读取的 `openclaw.json`。模板见 `reference/openclaw.template.json`。

> 注意：OPT 配置输入是 YAML，但本文件产物是 **JSON**（openclaw 运行时配置文件，格式固定）。

## 输入字段

- `opt.agents[]` → `agents.list`（main + 所有子 agent，各指定独立 workspace 路径）
- `opt.agents[].llm` → `models.providers`
- `opt.agents[].skills[]` → `skills.entries`（每个默认 `enabled: true`）
- `opt.agents[].tools[]` → `tools.alsoAllow`
- `opt.agents[].mcp[]` → `mcp.servers`
- `opt.agents[].sandbox` → 对应 agent 的沙箱配置

## 渲染步骤

1. 读取 `reference/openclaw.template.json`
2. 填充 `{{AGENT_LIST}}` `{{MODEL_PROVIDERS}}` `{{TOOLS_ALLOW}}` `{{SKILL_ENTRIES}}` `{{MCP_SERVERS}}`
3. `agents.defaults.skipBootstrap: true`、`executionContract: "strict-agentic"` 对所有 agent 默认开启
4. 写入 `~/.openclaw/output/<opt_id>/openclaw/openclaw.json`
5. 校验是合法 JSON（无尾逗号、占位符已全部替换）

## 纪律

- API Key / token 一律 ENV 占位（如 `$ENV:PROVIDER_API_KEY`、`${MCP_TOKEN}`），绝不写明文
- 沙箱默认最小权限；放开网络/挂载需配置显式声明
- 产物必须是合法 JSON
- 仅渲染本文件
