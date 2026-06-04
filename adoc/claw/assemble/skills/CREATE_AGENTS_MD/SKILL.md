---
name: CREATE_AGENTS_MD
description: 渲染 agent 的 AGENTS.md（角色定位、子 agent 路由、能力映射、Standing Orders、红线）
version: "1.0"
tools:
  - mc
---

# CREATE_AGENTS_MD

把某个 agent 的角色、能力、业务流、红线渲染成 `AGENTS.md`。模板见 `reference/AGENTS.template.md`。

## 输入字段

- `opt.agents[].role` — 角色定位（必填）
- `opt.agents[].routes[]` — **仅 main**：子 agent 路由规则，每项含 `when`（什么场景）+ `to`（转给哪个 agent id）+ `desc`（可选说明），渲染成 `{{SUBAGENT_ROUTING}}`
- `opt.agents[].capabilities[]` — 能力清单（含 `access: read|write`、`run`、`skill`），渲染成「能力与工具映射」表
- `opt.agents[].skills[]` — 技能列表；其中带 `usage[]`（典型 `source: prebuilt`、也可能是 hub/inline）的项，把 `usage` 当「何时使用」场景：
  - 该 skill 属 main 可路由的下游能力 → 并入 `{{SUBAGENT_ROUTING}}` 的 `when` 描述
  - 否则并入本 agent 「能力与工具映射」表的约束/何时使用列
  - `source: prebuilt` 项 assemble 不落盘 SKILL.md，但**必须**在此体现其 `usage`，否则该已传技能在蓝图里没有任何场景说明
- `opt.agents[].writeOrder[]` — 写操作依赖顺序，渲染成「创建类依赖顺序，不得跳序」
- `opt.agents[].dag` — `llm-judge` 型业务流 → 渲染成 Standing Orders 步骤（全命令/确认型不在此，由 xsystem 转成 Lobster 随 `workflows[]` 携带，交 CREATE_WORKFLOW_LOBSTER 落盘）
- `opt.agents[].redlines[]` — 红线条目

## 渲染步骤

1. 读取 `reference/AGENTS.template.md`
2. main agent 才填 `{{SUBAGENT_ROUTING}}`（来自 `routes[]`，逐条列成"遇到 `when` → 转交 `to`：`desc`"）；子 agent 该段留空或写"无下游 agent"
3. `capabilities[]` → `{{CAPABILITY_TABLE}}`（能力 / 类型 / 工具 / 约束 四列）；无 capabilities 则该表写"本 agent 无业务 CLI 能力"。带 `usage[]` 的 skill（尤其 `source: prebuilt`）在表中补一行，约束列写其使用场景
4. Standing Orders：read 能力 → 自主执行；write 能力 → Approval gate（先 `--dry-run` + 确认）；`llm-judge` DAG 节点按拓扑序展开为步骤；纯调度型 agent（只有 routes、无 capabilities/dag）Standing Orders 写路由纪律即可
5. `redlines[]` → `{{RED_LINES}}`；`writeOrder[]` 落入对应 Standing Order
6. 写入 `<agent_root>AGENTS.md`，即 `~/.openclaw/output/<opt_id>/workspace/<agent_id>/AGENTS.md`（main = `workspace/main/`）

## 纪律

- DAG 步骤严格按拓扑排序，不得自行决定顺序
- write 类能力必须带 Approval gate，不得省略
- 红线原样保留，不软化措辞
- 仅渲染本文件
