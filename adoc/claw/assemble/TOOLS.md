# TOOLS.md

## 配置来源

agent 拿到一份完整的 OPT 配置 JSON 即据此创建蓝图——**配置 JSON 直接解析，不通过 API 反查**。无论 OPT JSON 从哪个通道送达，处理方式一致：解析内容、渲染文件、写 MinIO。

## 平台 API（只读辅助）

- 查询知识库列表：`assemble-api list-kb --json`
- 查询 SKILL 列表：`assemble-api list-skills --json`
- 查询可用 LLM 模型：`assemble-api list-models --json`
- 装配任务状态登记/查询：`assemble-api list-tasks ...`（供 HEARTBEAT 补偿检查）

> 不再使用 `get-opt-config`（配置直接随请求到达，不反查）、不再使用 `write-workspace` / `mount` / `pod-status`（写入终点是 MinIO，挂载由 xsystem 调其他团队的服务负责，与本 agent 无关）。

## 写入 MinIO（蓝图真源）

渲染后的 workspace 文件通过 `gen-workspace` SKILL 用 `mc` 直接写入 MinIO。一套文件 = 一个 OPT 蓝图。

**路径约定（固定，装配过程中不得更改）：**

- mc alias：`kdx-minio`
- bucket：`assemble`（已预先创建，直接使用，不需新建）
- 远端前缀：`assemble/<username>/<TS>/openclaw/`
- `<username>`：发起本次装配的操作员标识（平台经 ENV 注入）
- `<TS>`：时间戳 `yyyyMMddHHmmss`，**整个装配生命周期只取一次并固定复用**（见下方红线）

```bash
# 装配开始时只取一次时间戳，之后全程复用，绝不重新取
TS=$(date +%Y%m%d%H%M%S)
LOCAL=~/.openclaw/output/<username>/$TS/openclaw
REMOTE=kdx-minio/assemble/<username>/$TS/openclaw

# 整目录上传一套蓝图（本地结构镜像远端）
mc cp --recursive "$LOCAL/" "$REMOTE/"
```

- 上传**只用 `mc`**，不使用 aws s3 或其他通道。
- MinIO 连接信息（endpoint / access key / secret）由平台经 ENV 注入并已配好 `kdx-minio` alias，不写进任何文件。
- 写入是装配 agent 对 MinIO 的**唯一写方向**；运行后操作员经 UI 改文件由 xsystem 写 MinIO，不经本 agent。

> **红线：时间戳只取一次。** 装配开始即固定 `$TS`，本地生成、远端上传的所有文件都用同一个 `$TS`。绝不在生成每个文件时各自调 `date`，否则一套蓝图会被打散到多个时间戳目录（如 USER.md 落在 `20260603113015/`、IDENTITY.md 落在 `20260603113020/`）。

## DAG 转换工具

> `dag2lobster` 是平台自行实现的内部工具，不是 openclaw 原生能力。

- DAG JSON → Lobster 工作流：`dag2lobster --input <dag.json> --output <workflow.lobster>`
- DAG 校验（检查环、孤立节点、缺失字段）：`dag2lobster --validate --input <dag.json>`

## 文件模板

workspace 文件按 `gen-workspace` SKILL 里的规范内联渲染，不依赖外部 `.tmpl` 文件。需要渲染的文件集：

- `IDENTITY.md` / `SOUL.md` / `USER.md` / `AGENTS.md` / `TOOLS.md` / `HEARTBEAT.md`
- `openclaw.json`（LLM 配置、SKILL 列表、MCP 服务、executionContract）
- `skills/<kb-name>/SKILL.md`（每个知识库一个）
- `skills/<ontology-name>/SKILL.md`（每个本体一个）
- `workflows/<flow-name>.lobster`（每个 DAG 一个，如有）

## 输出目录

路径由 `<username>` + 单次固定时间戳 `<TS>` 决定，本地与远端结构一致（均带 `openclaw/` 子目录）：

- 本地渲染暂存：`~/.openclaw/output/<username>/<TS>/openclaw/`
- MinIO 蓝图前缀：`kdx-minio/assemble/<username>/<TS>/openclaw/`

> 本地与远端镜像，可直接 `mc cp --recursive` 整目录上传，避免逐文件 cp 时路径漂移。

## 注意事项

- 渲染与写 MinIO 全自动执行，不等真人确认（真人确认前置在 UI 提交环节）
- MinIO 写入失败时不静默跳过，停下并报告具体失败的对象
- 生成文件时不打印用户填写的 LLM API Key 等敏感字段，API Key 一律写成 ENV 占位符
