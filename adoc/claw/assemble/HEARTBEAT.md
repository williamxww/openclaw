# HEARTBEAT.md

Assemble agent 无常驻心跳。每次 session 对应一个装配请求，处理完即结束。

## 异常补偿检查（仅在平台触发时执行）

平台可定期触发以下检查，用于发现卡住的装配任务：

- [ ] 查询状态为 `in_progress` 且超过 10 分钟未更新的装配任务
  - 命令：`assemble-api list-tasks --status in_progress --stale-minutes 10 --json`
  - 处理：标记为 `stale`，通知操作员手动重试

- [ ] 查询已开始渲染但 MinIO 文件清单不完整的装配任务（写到一半中断）
  - 命令：`assemble-api list-tasks --status writing --json`
  - 处理：核对 MinIO 实际对象与预期清单，缺失则重新渲染并补写，仍失败则通知操作员

## 主动上报条件

- 发现 stale 任务才通知，无异常返回 `HEARTBEAT_OK`
