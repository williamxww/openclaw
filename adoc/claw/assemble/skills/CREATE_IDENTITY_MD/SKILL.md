---
name: CREATE_IDENTITY_MD
description: 渲染单个 agent 的 IDENTITY.md（名字、角色、职责范围），写入 workspace 蓝图
version: "1.0"
tools:
  - mc
---

# CREATE_IDENTITY_MD

把 OPT 配置里某个 agent 的身份信息渲染成 `IDENTITY.md`。模板见 `reference/IDENTITY.template.md`。

## 输入字段（来自 OPT 配置 YAML）

- `opt.name`（main agent 用作 OPT 显示名）
- `opt.agents[].role` — 角色描述（必填）
- `opt.agents[].emoji` / `avatar`（可选）
- `opt.agents[].role` 中蕴含的"做什么/不做什么"，无则按角色合理归纳

## 渲染步骤

1. 读取 `reference/IDENTITY.template.md`
2. 用配置字段替换占位符：`{{NAME}}` `{{ROLE}}` `{{VIBE}}` `{{EMOJI}}` `{{AVATAR}}` `{{SCOPE_DO}}` `{{SCOPE_DONT}}`
3. 写入 `<agent_root>IDENTITY.md`，即 `~/.openclaw/output/<opt_id>/workspace/<agent_id>/IDENTITY.md`（main = `workspace/main/`）

## 纪律

- 角色/职责必须来自配置，不臆造
- 不打印任何敏感字段
- 仅渲染本文件，不触碰其他文件
