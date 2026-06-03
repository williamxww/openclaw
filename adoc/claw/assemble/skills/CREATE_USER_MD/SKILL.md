---
name: CREATE_USER_MD
description: 渲染 USER.md（服务对象画像、时区语言、权限边界），写入 workspace 蓝图
version: "1.0"
tools:
  - mc
---

# CREATE_USER_MD

把 OPT 配置里的 `opt.owner` 渲染成 `USER.md`。模板见 `reference/USER.template.md`。

## 输入字段

- 服务对象来源（按优先级）：**该 agent 自己的 `owner`**（如有）> 顶层 `opt.owner`
  - 即默认所有 agent 共用 `opt.owner`；某 agent 写了自己的 `owner:` 则用它覆盖
- `owner.name` / `role`（必填）
- `owner.timezone` / `language` / `address`（可选，缺省 Asia/Shanghai、中文优先）
- `owner.notes[]`（可选）→ `{{NOTES}}`
- 从该 agent 能力的 `access`/`permission` 归纳权限边界 → `{{PERMISSION_BOUNDARY}}`

## 渲染步骤

1. 读取 `reference/USER.template.md`
2. 解析服务对象：`opt.agents[].owner` 存在则用它，否则用顶层 `opt.owner`
3. 替换 `{{OWNER_NAME}}` `{{OWNER_ROLE}}` `{{OWNER_ADDRESS}}` `{{TIMEZONE}}` `{{LANGUAGE}}` `{{NOTES}}` `{{PERMISSION_BOUNDARY}}`
4. 写入 `<agent_root>USER.md`，即 `~/.openclaw/output/<opt_id>/workspace/<agent_id>/USER.md`（每个 agent 一份，main = `workspace/main/`）

## 纪律

- 服务对象信息来自 `owner`（agent 级优先，否则顶层），不臆造
- 不打印敏感字段
- 仅渲染本文件
