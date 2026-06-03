---
name: CREATE_CRON_JOBS
description: 把 agent 的周期任务渲染成 cron/jobs.json（业务轮询、定点报表、按时提醒）
version: "1.0"
tools:
  - mc
---

# CREATE_CRON_JOBS

把 `opt.agents[].heartbeat[]` 里的周期任务渲染成 `cron/jobs.json`。模板见 `reference/jobs.template.json`。

> 业务周期任务走定时任务，不进 HEARTBEAT.md（见 自动装配.md 6.5）。

## 输入字段（`opt.agents[].heartbeat[]`）

- 每项含 `text`（到点要做什么）+ `schedule`
- `schedule.kind`: `at` / `every`（`everyMs`）/ `cron`（`expr` + `tz`）

## 渲染步骤

1. 读取 `reference/jobs.template.json`
2. 每个周期项 → 一条 job：分配 `id`、填 `schedule`、`sessionTarget: "main"`、`agentId`、`payload.kind: "systemEvent"`、`payload.text`
3. 写入 `~/.openclaw/output/<opt_id>/openclaw/cron/jobs.json`
4. 无周期任务则不生成此文件
5. 校验是合法 JSON

## 纪律

- 产物必须是合法 JSON
- cron 表达式可解析；`at` 时间在未来
- 仅渲染本文件
