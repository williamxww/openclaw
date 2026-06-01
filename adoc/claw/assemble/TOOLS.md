# TOOLS.md

## 平台 API

- OPT 配置读取：`assemble-api get-opt-config --opt-id <id> --json`
- 文件写入 workspace：`assemble-api write-workspace --opt-id <id> --file <name> --stdin`
- 挂载 workspace 到 pod：`assemble-api mount --opt-id <id> --pod <pod-id>`
- 查询 pod 状态：`assemble-api pod-status --pod <pod-id> --json`
- 查询知识库列表：`assemble-api list-kb --json`
- 查询 SKILL 列表：`assemble-api list-skills --json`
- 查询可用 LLM 模型：`assemble-api list-models --json`

## DAG 转换工具

> `dag2lobster` 是平台自行实现的内部工具，不是 openclaw 原生能力。

- DAG JSON → Lobster 工作流：`dag2lobster --input <dag.json> --output <workflow.lobster>`
- DAG 校验（检查环、孤立节点、缺失字段）：`dag2lobster --validate --input <dag.json>`

## 文件模板

- workspace 文件模板目录：`/opt/assemble/templates/`
  - `AGENTS.md.tmpl`
  - `SOUL.md.tmpl`
  - `IDENTITY.md.tmpl`
  - `USER.md.tmpl`
  - `TOOLS.md.tmpl`
  - `HEARTBEAT.md.tmpl`
  - `openclaw.json.tmpl`
  - `SKILL.md.tmpl`（知识库 / 本体 SKILL）

## 输出目录

- 生成的 workspace 暂存路径：`/tmp/assemble/<opt-id>/`
- 挂载后的 pod workspace 路径：由 `assemble-api mount` 返回

## 注意事项

- 所有写操作（write-workspace、mount）必须经过 Approval gate
- `assemble-api` 调用失败时不重试写操作，先报告错误
- 生成文件时不打印用户填写的 LLM API Key 等敏感字段
