---
name: CREATE_ONTOLOGY_SKILL
description: 为每个业务本体渲染一个 ontology-<id>/SKILL.md（onto-cli 结构化查询）
version: "1.0"
tools:
  - mc
---

# CREATE_ONTOLOGY_SKILL

用户勾选的每个本体 → 一个独立 SKILL 文件。模板见 `reference/ontology-SKILL.template.md`。

## 输入字段（`opt.agents[].skills[]` 中 `kind: ontology` 的项）

- `id` / `displayName` / `domain`（必填）
- `permission`（如 `ontology:hr-leave:read`）

## 渲染步骤

1. 对每个 ontology 项，读取 `reference/ontology-SKILL.template.md`
2. 替换 `{{ONTO_ID}}` `{{ONTO_DISPLAY_NAME}}` `{{ONTO_DOMAIN}}` `{{ONTO_PERMISSION}}`
3. 写入 `<agent_root>skills/ontology-<id>/SKILL.md`
   - main agent：`~/.openclaw/output/<opt_id>/openclaw/skills/ontology-<id>/SKILL.md`
   - 子 agent：`~/.openclaw/output/<opt_id>/workspace/<sub_agent>/skills/ontology-<id>/SKILL.md`
4. 选 N 个本体就生成 N 个（一对一）

## 纪律

- 命名空间固定 `ontology-<id>`，工具固定 `onto-cli`
- 与知识库的差异：本体查结构化概念/关系（concept get / relation list / query），不是语义检索
- 一对一生成，不合并、不遗漏
