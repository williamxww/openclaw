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

- 本地暂存：`~/.openclaw/output/<username>/<TS>/openclaw/`
- MinIO 蓝图前缀：`kdx-minio/assemble/<username>/<TS>/openclaw/`（bucket `assemble` 已预建）
- `<TS>` = `yyyyMMddHHmmss`，**整个装配只取一次**，本地与远端全程复用同一个值
- 上传只用 `mc`，不用 aws s3
- `memory/YYYY-MM-DD.md` 装配日志的 MinIO 前缀字段按 `assemble/<username>/<TS>/openclaw/` 记录
