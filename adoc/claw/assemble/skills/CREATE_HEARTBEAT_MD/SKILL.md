---
name: CREATE_HEARTBEAT_MD
description: 渲染 HEARTBEAT.md（agent 保活/兜底巡检项）；业务周期任务不在此，走 CREATE_CRON_JOBS
version: "1.0"
tools:
  - mc
---

# CREATE_HEARTBEAT_MD

渲染 `HEARTBEAT.md`。模板见 `reference/HEARTBEAT.template.md`。

## 输入字段

- 仅当 agent 有"与具体业务无关的保活/兜底巡检"需求时才写内容
- `opt.agents[].heartbeat[]` 里的**业务周期任务**不写这里——它们由 CREATE_CRON_JOBS 落到 `cron/jobs.json`（见 自动装配.md 6.5）

## 渲染步骤

1. 读取 `reference/HEARTBEAT.template.md`
2. 无保活需求 → `{{HEARTBEAT_BODY}}` 写"无常驻心跳。每次 session 对应一个请求，处理完即结束。"
3. 有保活需求 → 列成简短 checklist，避免 token 浪费
4. 写入 `~/.openclaw/output/<opt_id>/openclaw/HEARTBEAT.md`

## 纪律

- 业务轮询不进 HEARTBEAT，一律走定时任务（cron/jobs.json）
- 仅渲染本文件
