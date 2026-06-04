# TOOLS.md

## 配置来源

agent 拿到一份完整的 OPT 配置（YAML 格式）即据此创建蓝图——**配置直接解析，不通过 API 反查**。无论 OPT 配置从哪个通道送达，处理方式一致：解析内容、渲染文件、写 MinIO。

> 选 YAML 而非 JSON：YAML 表达能力更丰富（多行文本、注释、锚点引用），更适合承载 agent 性格/角色描述、Standing Orders 这类长文本字段。

> 配置一次性完整送达，知识库 / SKILL / LLM 模型等信息都已在 YAML 里，**不反查任何接口**。

## 本 agent 用到的工具

- `mc` — MinIO 客户端，写蓝图真源（唯一写方向）

> 装配 agent 只依赖 `mc`。Lobster 业务流由程序预生成并已上传到 MinIO，本 agent **不做转换、不调 `dag2lobster`、不落盘**。
> 不使用任何 OPT 配置反查接口（配置随请求完整到达）；不使用 `write-workspace` / `mount` / `pod-status`（写入终点是 MinIO，挂载由 xsystem 调其他团队的服务负责，与本 agent 无关）。

## 写入 MinIO（蓝图真源）

各 `CREATE_*` SKILL 渲染后的 workspace 文件用 `mc` 直接写入 MinIO。一套文件 = 一个 OPT 蓝图。

**路径约定（固定，装配过程中不得更改）：**

- mc alias：`kdx-minio`
- bucket：`assemble`（已预先创建，直接使用，不需新建）
- 远端前缀：`assemble/<opt_id>/`（下含根下 `openclaw.json` 与各 agent 的 `workspace/<agent_id>/`）
- `<opt_id>`：本次 OPT 的唯一标识（取自 OPT 配置的 `opt.id`）

```bash
LOCAL=~/.openclaw/output/<opt_id>
REMOTE=kdx-minio/assemble/<opt_id>

# 整目录上传一套蓝图（本地结构镜像远端）
# 含根下 openclaw.json 与各 agent 的 workspace/<agent_id>/，一次传齐
mc cp --recursive "$LOCAL/" "$REMOTE/"
```

- 上传**只用 `mc`**，不使用 aws s3 或其他通道。
- MinIO 连接信息（endpoint / access key / secret）由平台经 ENV 注入并已配好 `kdx-minio` alias，不写进任何文件。
- 写入是装配 agent 对 MinIO 的**唯一写方向**；运行后操作员经 UI 改文件由 xsystem 写 MinIO，不经本 agent。

> **红线：一套蓝图只落一个 `<opt_id>/` 前缀。** 路径由 `opt.id` 唯一决定，装配全程不变；前缀下含根下 `openclaw.json` 与各 agent（含 main）的 `workspace/<agent_id>/`，本地与远端结构镜像，整目录上传。

## 业务流（Lobster）

> 若用户强制选用 Lobster 方案，业务流 `.lobster` 文件由 **程序生成、预上传到 MinIO**（与 `openclaw.json` 同机制，由 `opt.prebuilt.lobster: true` 声明）。
> 装配 agent **不做 DAG → Lobster 转换、不校验、不落盘、不读取**，整条 Lobster 链路与本 agent 无关。

## 文件模板

每个产物由对应的 `CREATE_*` SKILL 渲染，模板放在各 SKILL 自己的 `reference/` 子目录下（不依赖外部 `.tmpl` 文件）：

| 产物 | SKILL | 模板 |
|------|-------|------|
| `IDENTITY.md` | `CREATE_IDENTITY_MD` | `reference/IDENTITY.template.md` |
| `SOUL.md` | `CREATE_SOUL_MD` | `reference/SOUL.template.md` |
| `USER.md` | `CREATE_USER_MD` | `reference/USER.template.md` |
| `AGENTS.md` | `CREATE_AGENTS_MD` | `reference/AGENTS.template.md` |
| `TOOLS.md` | `CREATE_TOOLS_MD` | `reference/TOOLS.template.md` |
| `HEARTBEAT.md` | `CREATE_HEARTBEAT_MD` | `reference/HEARTBEAT.template.md` |
| `openclaw.json` | `CREATE_OPENCLAW_JSON` | `reference/openclaw.template.json` |
| `skills/kb-<id>/SKILL.md` | `CREATE_KB_SKILL` | `reference/kb-SKILL.template.md` |
| `skills/ontology-<id>/SKILL.md` | `CREATE_ONTOLOGY_SKILL` | `reference/ontology-SKILL.template.md` |
| `skills/<id>/SKILL.md` | `CREATE_PROGRAM_SKILL` | `reference/program-SKILL.template.md` |
| `cron/jobs.json` | `CREATE_CRON_JOBS` | `reference/jobs.template.json` |

> `openclaw.json` 与 `workflows/*.lobster` 若由 `opt.prebuilt` 声明为程序预生成，则不在上表、由程序上传，assemble 不渲染。

## 输出目录

路径由 `<opt_id>` 决定，本地与远端结构一致。前缀下分两部分：全局 `openclaw.json` 在根下，每个 agent（含 main）的文件在 `workspace/<agent_id>/`：

- 本地渲染暂存根：`~/.openclaw/output/<opt_id>/`
  - 全局配置：`~/.openclaw/output/<opt_id>/openclaw.json`（根下）
  - 每个 agent：`~/.openclaw/output/<opt_id>/workspace/<agent_id>/`（main = `workspace/main/`）
- MinIO 蓝图前缀：`kdx-minio/assemble/<opt_id>/`（镜像同样结构）

> 本地与远端镜像，从 `<opt_id>/` 根 `mc cp --recursive` 整目录上传，一次传齐根下 `openclaw.json` 与 `workspace/`，避免漏传或路径漂移。

## 注意事项

- 渲染与写 MinIO 全自动执行，不等真人确认（真人确认前置在 UI 提交环节）
- MinIO 写入失败时不静默跳过，停下并报告具体失败的对象
- 生成文件时不打印用户填写的 LLM API Key 等敏感字段，API Key 一律写成 ENV 占位符
