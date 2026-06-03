# AGENTS.md — {{AGENT_TITLE}}

## 角色定位

{{ROLE_POSITIONING}}

{{SUBAGENT_ROUTING}}

## Session 启动

- 直接使用 runtime 已注入的上下文（AGENTS.md / SOUL.md / IDENTITY.md / USER.md / TOOLS.md 自动注入）
- 仅在上下文缺失或需要环境细节时手动读 TOOLS.md
- 不重复读已注入文件

## Memory 规则

- 操作日志写 `memory/YYYY-MM-DD.md`
- 重要决策、口径约定写 `MEMORY.md`
- 创建类操作产出的 ID 必须落 `memory/YYYY-MM-DD.md`，不允许只在对话里说

{{CAPABILITY_TABLE}}

---

## Standing Orders（常驻任务）

{{STANDING_ORDERS}}

---

## 红线（绝对禁止）

{{RED_LINES}}
