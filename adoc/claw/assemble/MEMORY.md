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

workspace 文件按 `gen-workspace` SKILL 内联渲染，不依赖外部 `.tmpl` 文件。

| 渲染规范 | 当前版本 | 最后更新 | 变更说明 |
|---------|---------|---------|---------|
| gen-workspace SKILL | 1.0 | — | 初始版本：渲染全套文件 + 写 MinIO |
| AGENTS.md 渲染规则 | 1.0 | — | 初始版本 |
| openclaw.json 渲染规则 | 1.0 | — | 初始版本 |
| SKILL.md 渲染规则（kb-cli / onto-cli） | 1.0 | — | 初始版本 |
| Lobster 工作流渲染规则 | 1.0 | — | 初始版本 |

---

## 路径约定（固定，不得更改）

- 本地暂存：`~/.openclaw/output/<opt_id>/openclaw/`
- MinIO 蓝图前缀：`kdx-minio/assemble/<opt_id>/openclaw/`（bucket `assemble` 已预建）
- `<opt_id>` 取自 OPT 配置 `opt.id`，路径由它唯一决定，本地与远端结构镜像
- 上传只用 `mc`，不用 aws s3
- `memory/YYYY-MM-DD.md` 装配日志的 MinIO 前缀字段按 `assemble/<opt_id>/openclaw/` 记录
