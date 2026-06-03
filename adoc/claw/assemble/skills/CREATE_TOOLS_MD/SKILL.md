---
name: CREATE_TOOLS_MD
description: 渲染 TOOLS.md（业务 CLI 端点、命令别名、连接约定），写入 workspace 蓝图
version: "1.0"
tools:
  - mc
---

# CREATE_TOOLS_MD

把 agent 用到的业务 CLI 渲染成 `TOOLS.md`。模板见 `reference/TOOLS.template.md`。

## 输入字段

- `opt.agents[].tools[]` — 每个含 `name` / `displayName` / `env[]`（凭证占位）/ `defaultFormat`
- `opt.agents[].capabilities[].run` — 命令示例，按只读/写操作分节

## 渲染步骤

1. 读取 `reference/TOOLS.template.md`
2. 每个 CLI 一节，列出连接信息、命令示例、输出格式；`{{CLI_SECTIONS}}`
3. 把"只读账号""写操作需 dry-run""结果回写 memory"等约束写进 `{{NOTES}}`
4. 写入 `<agent_root>TOOLS.md`
   - main agent：`~/.openclaw/output/<opt_id>/openclaw/TOOLS.md`
   - 子 agent：`~/.openclaw/output/<opt_id>/workspace/<sub_agent>/TOOLS.md`

## 纪律

- 凭证一律 ENV 占位（如 `$ENV:WATER_OPT_TOKEN`），绝不写明文
- 命令示例来自 `capabilities[].run`，不杜撰参数
- 仅渲染本文件
