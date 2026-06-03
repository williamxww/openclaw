---
name: CREATE_SOUL_MD
description: 渲染单个 agent 的 SOUL.md（性格、语气、边界），写入 workspace 蓝图
version: "1.0"
tools:
  - mc
---

# CREATE_SOUL_MD

把 OPT 配置里某个 agent 的 `soul` 字段渲染成 `SOUL.md`。模板见 `reference/SOUL.template.md`。

## 输入字段

- `opt.agents[].soul` — 性格/语气描述（必填，多行 YAML 文本）

## 渲染步骤

1. 读取 `reference/SOUL.template.md`
2. 从 `soul` 提炼：核心气质 → `{{CORE_TRAITS}}`、边界 → `{{BOUNDARIES}}`、一句 Vibe → `{{VIBE_PARAGRAPH}}`
3. 写入 `<agent_root>SOUL.md`，即 `~/.openclaw/output/<opt_id>/workspace/<agent_id>/SOUL.md`（main = `workspace/main/`）

## 纪律

- 性格内容必须来自 `soul`，不自行加戏
- 不打印敏感字段
- 仅渲染本文件
