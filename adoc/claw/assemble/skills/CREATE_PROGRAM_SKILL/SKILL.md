---
name: CREATE_PROGRAM_SKILL
description: 为程序型自定义 skill（非 kb、非 ontology，如 nl2sql）渲染 skills/<id>/SKILL.md
version: "1.0"
tools:
  - mc
---

# CREATE_PROGRAM_SKILL

为 `kind` 既非 `kb` 也非 `ontology` 的自定义能力 skill 渲染 SKILL.md（如 `nl2sql`）。模板见 `reference/program-SKILL.template.md`。

## 输入字段（`opt.agents[].skills[]` 中 `source: inline` 且 `kind` 非 kb/ontology 的项）

> 只处理现场定义型（`source: inline`，缺省即 inline）。`source: hub` 的技能由 CREATE_HUB_SKILL 原样落盘，不在此渲染。

- `kind`（如 `nl2sql`）/ `id` / `displayName` / `domain`
- `tools[]`（依赖的业务 CLI，如 `water-cli`）
- `permission`（如 `data:warehouse:read`）

## 渲染步骤

1. 读取 `reference/program-SKILL.template.md`
2. 替换 `{{SKILL_ID}}` `{{SKILL_DISPLAY_NAME}}` `{{SKILL_DOMAIN}}` `{{SKILL_TOOLS}}` `{{SKILL_PERMISSION}}`
3. 按能力补充"何时使用 / 执行流程 / 执行纪律"——这些来自该 agent 的 capabilities 与红线
4. 写入 `<agent_root>skills/<id>/SKILL.md`，即 `~/.openclaw/output/<opt_id>/workspace/<agent_id>/skills/<id>/SKILL.md`（main = `workspace/main/`）

## 纪律

- kb / ontology 不走本 skill（各有专用 CREATE_*）
- 工具依赖写进 `metadata.requires.bins`
- 权限边界、只读/写约束如实写明
