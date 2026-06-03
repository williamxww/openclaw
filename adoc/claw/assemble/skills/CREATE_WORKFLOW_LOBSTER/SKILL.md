---
name: CREATE_WORKFLOW_LOBSTER
description: 把全命令/确认型 DAG 经 dag2lobster 转换成 workflows/<id>.lobster
version: "1.0"
tools:
  - mc
  - dag2lobster
---

# CREATE_WORKFLOW_LOBSTER

把 agent 的 DAG（全为 command/approval/condition 节点）转换成 Lobster 工作流。模板见 `reference/workflow.template.lobster`。

> 含 `llm-judge` 节点的 DAG 不在此——那类走 CREATE_AGENTS_MD 渲染成 Standing Orders。

## 输入字段（`opt.agents[].dag`）

- `id` / `name` / `nodes[]`
- 节点 `type`: `command` / `approval` / `condition` / `agent-task`

## 渲染步骤

1. 先校验：`dag2lobster --validate --input <dag.yaml>`（检查环、孤立节点、缺字段）
2. 转换：`dag2lobster --input <dag.yaml> --output <flow>.lobster`
   - `command` → step `{ id, command }`
   - `approval` → step + `approval: required`
   - `condition` → step + `condition: $<gate>.approved`
   - 边 A→B → `B.stdin = $A.stdout`
   - `agent-task` → `command: agent-invoke --agent <id> --task <label>`
3. 写入 `<agent_root>workflows/<flow-id>.lobster`，即 `~/.openclaw/output/<opt_id>/workspace/<agent_id>/workflows/<flow-id>.lobster`（main = `workspace/main/`）
4. 转换后再 `dag2lobster --validate` 二次校验

## 纪律

- 节点 id 保持一致，严格按拓扑排序，不自行决定顺序
- 校验失败立即停止，返回具体错误节点
- 仅渲染本文件
