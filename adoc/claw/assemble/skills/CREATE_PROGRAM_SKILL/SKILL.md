---
name: CREATE_PROGRAM_SKILL
description: 为程序型自定义 skill（非 kb、非 ontology，如 nl2sql）渲染 skills/<id>/SKILL.md
version: "1.0"
tools:
  - mc
---

# CREATE_PROGRAM_SKILL

为 `kind` 既非 `kb` 也非 `ontology` 的自定义能力 skill 渲染 SKILL.md（如 `nl2sql`）。模板见 `reference/program-SKILL.template.md`。

## 输入字段（`opt.agents[].skills[]` 中其他 `kind` 的项）

- `kind`（如 `nl2sql`）/ `id` / `displayName` / `domain`
- `tools[]`（依赖的业务 CLI，如 `water-cli`）
- `permission`（如 `data:warehouse:read`）

## 渲染步骤

1. 读取 `reference/program-SKILL.template.md`
2. 替换 `{{SKILL_ID}}` `{{SKILL_DISPLAY_NAME}}` `{{SKILL_DOMAIN}}` `{{SKILL_TOOLS}}` `{{SKILL_PERMISSION}}`
3. 按能力补充"何时使用 / 执行流程 / 执行纪律"——这些来自该 agent 的 capabilities 与红线
4. 写入 `~/.openclaw/output/<opt_id>/openclaw/skills/<id>/SKILL.md`

## 纪律

- kb / ontology 不走本 skill（各有专用 CREATE_*）
- 工具依赖写进 `metadata.requires.bins`
- 权限边界、只读/写约束如实写明
