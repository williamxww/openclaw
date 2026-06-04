---
name: CREATE_HUB_SKILL
description: 把从 SKILL HUB 选定、由 xsystem 预先注入完整内容的技能原样落成 skills/<dir>/SKILL.md
version: "1.0"
tools:
  - mc
---

# CREATE_HUB_SKILL

处理 `opt.agents[].skills[]` 中 `source: hub` 的项——这些是用户从 **SKILL HUB** 选的已有技能，xsystem 已把成品 SKILL.md 文本注入到配置里。

> 与 Lobster 同思路：装配 agent **不访问 HUB、不渲染、不改写**，只把 `content` 原样落盘。

## 输入字段（`opt.agents[].skills[]` 中 `source: hub` 的项）

- `id` — HUB 技能标识
- `version` — 选定版本（仅记录用，不影响落盘）
- `dir` — 落点目录名 → `skills/<dir>/`
- `content` — xsystem 从 HUB 取出的完整 SKILL.md 文本（多行）
- `referenceFiles[]`（可选）— 该技能自带的参考文件落点清单

## 渲染步骤

1. 对每个 `source: hub` 项，取其 `content`
2. 原样写入 `<agent_root>skills/<dir>/SKILL.md`，即 `~/.openclaw/output/<opt_id>/workspace/<agent_id>/skills/<dir>/SKILL.md`（main = `workspace/main/`）
3. 有 `referenceFiles[]` 则把对应文件放入同目录 `reference/` 子目录
4. agent 的 `skills[]` 里没有 `source: hub` 项则跳过

## 纪律

- 内容原样落盘，不增删、不重排、不"优化"
- 不访问 SKILL HUB，不做任何渲染——内容已由 xsystem 备好
- `source: inline` 的项不在此处理（kb → CREATE_KB_SKILL，ontology → CREATE_ONTOLOGY_SKILL，program → CREATE_PROGRAM_SKILL）
- `source: prebuilt` 的项也不在此处理：其 SKILL.md 已由程序上传到 `skills/<dir>/`，**不落盘、不读取**，仅由 CREATE_AGENTS_MD 取其 `usage` 写场景
- 仅渲染本文件