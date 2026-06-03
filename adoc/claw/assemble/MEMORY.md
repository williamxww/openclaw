# MEMORY.md

重要决策、已知问题、经验教训。日常装配日志写 `memory/YYYY-MM-DD.md`，不写这里。

---

## 已知问题

（初始为空，运行中积累）

---

## 经验教训

（初始为空，运行中积累）

---

## 渲染规范版本记录

每个产物由独立的 `CREATE_*` SKILL 渲染，模板放在各 SKILL 自己的 `reference/` 子目录下。

| CREATE_* SKILL | 产物 | 当前版本 | 最后更新 |
|---------------|------|---------|---------|
| CREATE_IDENTITY_MD | IDENTITY.md | 1.0 | — |
| CREATE_SOUL_MD | SOUL.md | 1.0 | — |
| CREATE_USER_MD | USER.md | 1.0 | — |
| CREATE_AGENTS_MD | AGENTS.md | 1.0 | — |
| CREATE_TOOLS_MD | TOOLS.md | 1.0 | — |
| CREATE_HEARTBEAT_MD | HEARTBEAT.md | 1.0 | — |
| CREATE_OPENCLAW_JSON | openclaw.json | 1.0 | — |
| CREATE_KB_SKILL | skills/kb-*/SKILL.md | 1.0 | — |
| CREATE_ONTOLOGY_SKILL | skills/ontology-*/SKILL.md | 1.0 | — |
| CREATE_PROGRAM_SKILL | skills/*/SKILL.md（source:inline） | 1.0 | — |
| CREATE_HUB_SKILL | skills/*/SKILL.md（source:hub，原样落盘） | 1.0 | — |
| CREATE_CRON_JOBS | cron/jobs.json | 1.0 | — |
| CREATE_WORKFLOW_LOBSTER | workflows/*.lobster | 1.0 | — |

---

## 路径约定（固定，不得更改）

- 本地暂存根：`~/.openclaw/output/<opt_id>/`（全局 `openclaw.json` 在根下；每个 agent 在 `workspace/<agent_id>/`，main = `workspace/main/`）
- MinIO 蓝图前缀：`kdx-minio/assemble/<opt_id>/`（bucket `assemble` 已预建，镜像同样结构）
- `<opt_id>` 取自 OPT 配置 `opt.id`，路径由它唯一决定，本地与远端结构镜像
- 上传只用 `mc`，不用 aws s3
- `memory/YYYY-MM-DD.md` 装配日志的 MinIO 前缀字段按 `assemble/<opt_id>/` 记录
