---
name: CREATE_KB_SKILL
description: 为每个知识库渲染一个 kb-<id>/SKILL.md（kb-cli 检索），并放置上传的参考文件
version: "1.0"
tools:
  - mc
---

# CREATE_KB_SKILL

用户勾选的每个知识库 → 一个独立 SKILL 文件。模板见 `reference/kb-SKILL.template.md`。

## 输入字段（`opt.agents[].skills[]` 中 `kind: kb` 的项）

- `id` / `displayName` / `domain`（必填）
- `permission`（如 `kb:hr-policy:read`）
- `referenceFiles[]`（用户上传的参考文件相对路径）
- `sampleQuestions[]`（可选）

## 渲染步骤

1. 对每个 kb 项，读取 `reference/kb-SKILL.template.md`
2. 替换 `{{KB_ID}}` `{{KB_DISPLAY_NAME}}` `{{KB_DOMAIN}}` `{{KB_PERMISSION}}` `{{REFERENCE_FILES}}`
3. 写入 `<agent_root>skills/kb-<id>/SKILL.md`，即 `~/.openclaw/output/<opt_id>/workspace/<agent_id>/skills/kb-<id>/SKILL.md`（main = `workspace/main/`）
4. 把上传的参考文件放入同目录 `reference/` 子目录
5. 选 N 个知识库就生成 N 个（一对一）

## 纪律

- 命名空间固定 `kb-<id>`，工具固定 `kb-cli`
- 一对一生成，不合并、不遗漏
- 仅渲染 kb 类 SKILL，本体走 CREATE_ONTOLOGY_SKILL
