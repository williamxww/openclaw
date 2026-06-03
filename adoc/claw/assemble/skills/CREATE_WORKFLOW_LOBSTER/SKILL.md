---
name: CREATE_WORKFLOW_LOBSTER
description: 把 OPT 配置里已携带的 Lobster 工作流内容直接落成 workflows/<id>.lobster 文件
version: "1.0"
tools:
  - mc
---

# CREATE_WORKFLOW_LOBSTER

把 OPT 配置里**已经转换好的** Lobster 工作流内容原样写成 `.lobster` 文件。

> DAG → Lobster 的转换与校验已在 xsystem 侧完成，配置 YAML 直接携带完整的 Lobster 文本。本 SKILL **不做任何转换、不调用 `dag2lobster`、不理解 DAG 结构**，只负责落盘。

## 输入字段（`opt.agents[].workflows[]`）

- 每项含 `id`（工作流标识）+ `lobster`（完整的 Lobster 工作流内容，多行文本）

## 渲染步骤

1. 对每个 workflow 项，取其 `lobster` 字段内容
2. 原样写入 `<agent_root>workflows/<id>.lobster`，即 `~/.openclaw/output/<opt_id>/workspace/<agent_id>/workflows/<id>.lobster`（main = `workspace/main/`）
3. 配置无 `workflows[]` 则不生成此文件

## 纪律

- 内容原样落盘，不增删、不重排、不"优化"步骤
- 不做语法转换或拓扑排序——那是 xsystem 的职责
- 仅渲染本文件
