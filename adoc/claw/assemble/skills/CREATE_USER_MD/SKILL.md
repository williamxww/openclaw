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

- `opt.owner.name` / `role`（必填）
- `opt.owner.timezone` / `language` / `address`（可选，缺省 Asia/Shanghai、中文优先）
- 从各 agent 能力的 `access`/`permission` 归纳权限边界

## 渲染步骤

1. 读取 `reference/USER.template.md`
2. 替换 `{{OWNER_NAME}}` `{{OWNER_ROLE}}` `{{OWNER_ADDRESS}}` `{{TIMEZONE}}` `{{LANGUAGE}}` `{{NOTES}}` `{{PERMISSION_BOUNDARY}}`
3. 写入 `~/.openclaw/output/<opt_id>/openclaw/USER.md`

## 纪律

- 服务对象信息来自 `opt.owner`，不臆造
- 不打印敏感字段
- 仅渲染本文件
