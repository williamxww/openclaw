---
name: gen-workspace
description: 把 OPT 配置 JSON 渲染成一套 workspace markdown 文件，并直接写入 MinIO 蓝图
version: "1.0"
metadata: { "openclaw": { "requires": { "bins": ["mc", "dag2lobster"] } } }
tools:
  - mc
  - dag2lobster
---

# 生成 workspace 蓝图

装配 Agent 的核心能力 SKILL。输入是一份完整的 OPT 配置 JSON，输出是一套写入 MinIO 的 workspace markdown 文件——**一套文件 = 一个 OPT 蓝图**。配置 JSON 从哪个通道送达不影响处理。

## 何时使用

- 拿到一份"创建 OPT" / "更新 OPT"的 OPT 配置 JSON 时
- 不用于：pod 挂载、业务执行、知识库内容维护（均不在装配 agent 职责内）

## 输入

OPT 配置 JSON，结构见 `自动装配.md` 2.2。关键字段：

- `opt.id` / `opt.name` / `opt.owner.{name,role,timezone,language}`
- `opt.agents[]`：每个含 `id` / `role` / `soul` / `llm.modelId` / `skills[]` / `heartbeat[]` / `dag`

## 渲染规则

**先固定路径，再渲染。** 路径由 `opt.id` 唯一决定，装配全程不变：

```bash
LOCAL=~/.openclaw/output/<opt_id>/openclaw
mkdir -p "$LOCAL"
```

逐一渲染到本地暂存 `$LOCAL/`（即 `~/.openclaw/output/<opt_id>/openclaw/`），再整体写 MinIO。各文件内容来源：

| 文件 | 内容来源 |
|------|---------|
| `IDENTITY.md` | `opt.name`、main agent 的 `role`、职责范围 |
| `SOUL.md` | agent 的 `soul`（性格、语气、边界） |
| `USER.md` | `opt.owner`（姓名、职位、时区、语言） |
| `AGENTS.md` | 角色定位 + 子 agent 路由 + Standing Orders（DAG → 步骤） |
| `TOOLS.md` | 该 OPT 用到的业务 CLI 端点与命令别名 |
| `HEARTBEAT.md` | `opt.agents[].heartbeat`（如有，否则写"无常驻心跳"） |
| `openclaw.json` | LLM 配置、SKILL 列表、MCP、executionContract |
| `skills/kb-<id>/SKILL.md` | 每个知识库一个，工具 `kb-cli` |
| `skills/ontology-<id>/SKILL.md` | 每个本体一个，工具 `onto-cli` |
| `workflows/<flow>.lobster` | 每个 DAG 一个，经 `dag2lobster` 转换 |

### openclaw.json 渲染要点

- `agents.list` 含 main + 所有子 agent，各指定独立 workspace 路径
- `agents.defaults.skipBootstrap: true`、`executionContract: "strict-agentic"`
- LLM 写入 `models.providers`，API Key 一律 ENV 占位符（如 `"$ENV:PROVIDER_API_KEY"`），**绝不写明文**
- SKILL 列表写入 `skills.entries`，每个默认 `enabled: true`
- MCP server（如配置）写入 `mcp.servers`，token 用 `${ENV}` 占位

### DAG 渲染要点

- 全为命令/确认节点 → 经 `dag2lobster` 生成 `.lobster`，节点 id 保持一致
- 含 `llm-judge`（需 LLM 研判）节点 → 输出成 AGENTS.md 的 Standing Orders 片段，不生成 lobster
- 生成后用 `dag2lobster --validate` 二次校验

## 写入 MinIO

整套文件写到 `kdx-minio/assemble/<opt_id>/openclaw/`（bucket `assemble` 已预建，直接用），本地与远端结构镜像，保持目录结构。**只用 `mc`，不用 aws s3**：

```bash
# $LOCAL 沿用渲染阶段固定的值
mc cp --recursive "$LOCAL/" "kdx-minio/assemble/<opt_id>/openclaw/"
```

逐对象核对返回状态。任一失败立即停止并报告该对象，不留半套蓝图。

> 一套蓝图只落一个 `<opt_id>/openclaw/` 前缀，路径由 `opt.id` 唯一决定，本地与远端镜像，整目录上传。

## 执行纪律

- 渲染全自动，不中途停等人工确认（真人确认前置在 UI 提交环节）
- 校验失败不生成任何文件；要么整套写成功，要么不写
- 不打印任何敏感字段；API Key / 密码一律 ENV 占位符
- 只写本次 `<opt_id>/openclaw/` 前缀，绝不碰其他蓝图
- 写完回流文件清单给 xsystem，本次装配即结束——不挂载 pod
