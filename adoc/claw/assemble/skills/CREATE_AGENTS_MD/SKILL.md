---
name: CREATE_AGENTS_MD
description: 渲染 agent 的 AGENTS.md（角色定位、子 agent 路由、能力映射、Standing Orders、红线）
version: "1.0"
tools:
  - mc
  - dag2lobster
---

# CREATE_AGENTS_MD

把某个 agent 的角色、能力、业务流、红线渲染成 `AGENTS.md`。模板见 `reference/AGENTS.template.md`。

## 输入字段

- `opt.agents[].role` — 角色定位（必填）
- `opt.agents[].capabilities[]` — 能力清单（含 `access: read|write`、`run`、`skill`），渲染成「能力与工具映射」表
- `opt.agents[].writeOrder[]` — 写操作依赖顺序，渲染成「创建类依赖顺序，不得跳序」
- `opt.agents[].dag` — 业务流：含 `llm-judge` 节点 → 渲染成 Standing Orders 步骤；全命令/确认 → 交 CREATE_WORKFLOW_LOBSTER，本文件只写触发条件
- `opt.agents[].redlines[]` — 红线条目
- main agent：把所有子 agent 列成路由规则 `{{SUBAGENT_ROUTING}}`

## 渲染步骤

1. 读取 `reference/AGENTS.template.md`
2. main agent 才填 `{{SUBAGENT_ROUTING}}`，子 agent 留空
3. `capabilities[]` → `{{CAPABILITY_TABLE}}`（能力 / 类型 / 工具 / 约束 四列）
4. Standing Orders：read 能力 → 自主执行；write 能力 → Approval gate（先 `--dry-run` + 确认）；`llm-judge` DAG 节点按拓扑序展开为步骤
5. `redlines[]` → `{{RED_LINES}}`；`writeOrder[]` 落入对应 Standing Order
6. 写入 `<agent_root>AGENTS.md`，即 `~/.openclaw/output/<opt_id>/workspace/<agent_id>/AGENTS.md`（main = `workspace/main/`）

## 纪律

- DAG 步骤严格按拓扑排序，不得自行决定顺序
- write 类能力必须带 Approval gate，不得省略
- 红线原样保留，不软化措辞
- 仅渲染本文件
