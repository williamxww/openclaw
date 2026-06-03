---
name: CREATE_ONTOLOGY_SKILL
description: 为每个业务本体渲染一个 ontology-<id>/SKILL.md（onto-cli 结构化查询）
version: "1.0"
tools:
  - mc
---

# CREATE_ONTOLOGY_SKILL

用户勾选的每个本体 → 一个独立 SKILL 文件。模板见 `reference/ontology-SKILL.template.md`。

## 输入字段（`opt.agents[].skills[]` 中 `source: inline` 且 `kind: ontology` 的项）

> 只处理现场定义型（`source: inline`，缺省即 inline）。`source: hub` 的技能由 CREATE_HUB_SKILL 原样落盘，不在此渲染。

- `id` / `displayName` / `domain`（必填）
- `permission`（如 `ontology:hr-leave:read`）

## 渲染步骤

1. 对每个 ontology 项，读取 `reference/ontology-SKILL.template.md`
2. 替换 `{{ONTO_ID}}` `{{ONTO_DISPLAY_NAME}}` `{{ONTO_DOMAIN}}` `{{ONTO_PERMISSION}}`
3. 写入 `<agent_root>skills/ontology-<id>/SKILL.md`，即 `~/.openclaw/output/<opt_id>/workspace/<agent_id>/skills/ontology-<id>/SKILL.md`（main = `workspace/main/`）
4. 选 N 个本体就生成 N 个（一对一）

## 纪律

- 命名空间固定 `ontology-<id>`，工具固定 `onto-cli`
- 与知识库的差异：本体查结构化概念/关系（concept get / relation list / query），不是语义检索
- 一对一生成，不合并、不遗漏
