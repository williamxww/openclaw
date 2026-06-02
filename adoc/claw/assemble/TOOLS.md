# TOOLS.md

## 配置来源

OPT 配置**不通过 API 反查**，而是由 xsystem 经对话通道（`msg.send`）把完整的 OPT JSON 直接放进消息体发来。agent 收到后直接解析消息内容即可，无需调接口拉配置。

## 平台 API（只读辅助）

- 查询知识库列表：`assemble-api list-kb --json`
- 查询 SKILL 列表：`assemble-api list-skills --json`
- 查询可用 LLM 模型：`assemble-api list-models --json`
- 装配任务状态登记/查询：`assemble-api list-tasks ...`（供 HEARTBEAT 补偿检查）

> 不再使用 `get-opt-config`（配置随消息体到达）、不再使用 `write-workspace` / `mount` / `pod-status`（写入终点是 MinIO，挂载由 xsystem 调其他团队的服务负责，与本 agent 无关）。

## 写入 MinIO（蓝图真源）

渲染后的 workspace 文件通过 `gen-workspace` SKILL 直接写入 MinIO，用 MinIO 客户端落对象。一套文件 = 一个 OPT 蓝图，bucket / 前缀按 `opt-id` 归位：

```bash
# 单文件写入（从 stdin 渲染内容写到 MinIO 对象）
mc pipe minio/opt-blueprints/<opt-id>/IDENTITY.md < /tmp/assemble/<opt-id>/IDENTITY.md

# 或整目录上传一套蓝图
mc cp --recursive /tmp/assemble/<opt-id>/ minio/opt-blueprints/<opt-id>/

# 等价的 aws s3 写法（endpoint 指向 MinIO）
aws --endpoint-url "$MINIO_ENDPOINT" s3 cp --recursive /tmp/assemble/<opt-id>/ s3://opt-blueprints/<opt-id>/
```

- MinIO 连接信息（endpoint / access key / secret）由平台经 ENV 注入，不写进任何文件。
- 写入是装配 agent 对 MinIO 的**唯一写方向**；运行后操作员经 UI 改文件由 xsystem 写 MinIO，不经本 agent。

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

- 渲染暂存路径（本地 /tmp，写完即上传 MinIO）：`/tmp/assemble/<opt-id>/`
- MinIO 蓝图前缀：`minio/opt-blueprints/<opt-id>/`

## 注意事项

- 渲染与写 MinIO 全自动执行，不等真人确认（真人确认前置在 UI 提交环节）
- MinIO 写入失败时不静默跳过，停下并报告具体失败的对象
- 生成文件时不打印用户填写的 LLM API Key 等敏感字段，API Key 一律写成 ENV 占位符
