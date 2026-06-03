# HEARTBEAT.md

无常驻心跳。装配 Agent 每次 session 对应一个装配请求，处理完即结束，不保持长期 session、不做周期巡检。

卡住/中断的装配任务由平台侧的调度或补偿机制处理，不在本 agent 职责内。
