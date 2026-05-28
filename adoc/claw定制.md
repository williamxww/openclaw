# OpenClaw 定制方案（不修改源码）

> 目标：在不动 `openclaw/` 源码的前提下，把 OpenClaw 改造成一只属于自己的 claw——
> 自定义 agent 名称、模型、人格、系统提示、Skill、工具、工作流。
> 所有改动只落地在 **配置文件 + 外置目录 + 独立插件包**，升级 OpenClaw 时无需合并冲突。

---

## 0. 核心原则

| 原则 | 落点 |
| --- | --- |
| 不改源码 | `openclaw/src/**`、`openclaw/extensions/**` 一行不动 |
| 配置驱动 | `~/.openclaw/openclaw.json`（或 `--dev` 时 `~/.openclaw-dev/openclaw.json`） |
| 文件驱动 | workspace 目录里的 markdown / skill 目录 / hooks 目录 |
| 插件驱动 | 自定义工具走独立 npm 包形态的插件，`openclaw plugins install` |
| 可升级 | 整个 `my-claw/` 仓库自治，OpenClaw 升版本不影响 |

---

## 1. 推荐目录布局

把所有定制收敛到一个仓库（示例 `D:/my-claw/`），独立 git 管理：

```
D:/my-claw/
├─ openclaw.json              # 复制/软链 → ~/.openclaw/openclaw.json
├─ workspace/                 # agent 工作区（系统提示来源）
│  ├─ AGENTS.md               # 操作指令（系统提示主体）
│  ├─ SOUL.md                 # 人格、语气、边界
│  ├─ IDENTITY.md             # 名字、emoji、自我形象
│  ├─ USER.md                 # 用户身份与称呼
│  ├─ TOOLS.md                # 工具使用约定（guidance）
│  ├─ MEMORY.md               # 长期记忆（可选）
│  ├─ memory/YYYY-MM-DD.md    # 每日笔记
│  └─ skills/                 # 工作区独占 Skill（最高优先级）
├─ skills/                    # 跨 agent 共享 Skill（走 extraDirs）
├─ plugins/                   # 自定义工具插件（每个一个独立包）
│  └─ my-tools/
│     ├─ openclaw.plugin.json
│     ├─ package.json
│     └─ index.ts
├─ hooks/                     # 事件钩子
│  └─ session-snapshot/
│     ├─ HOOK.md
│     └─ handler.ts
└─ workflows/                 # standing orders / cron / taskflow
   └─ daily-report.md
```

---

## 2. Agent 名称、模型、Provider

全部写在 `~/.openclaw/openclaw.json`（JSON5 允许注释和单引号）：

```json5
{
  agents: {
    defaults: {
      workspace: "D:/my-claw/workspace",
      model: "anthropic/claude-sonnet-4-6",
      // 关闭 bootstrap 自动生成（自带模板已就位）
      skipBootstrap: false,
      bootstrapMaxChars: 12000,
      bootstrapTotalMaxChars: 60000,
    },
    list: [
      {
        id: "main",
        name: "克拉夫",                 // 展示名
        default: true,
        workspace: "D:/my-claw/workspace",
        agentDir: "~/.openclaw/agents/main/agent",
        model: "anthropic/claude-sonnet-4-6",
        skills: ["my-search", "github"], // skill 白名单（空数组=禁用全部）
      },
      {
        id: "coding",
        name: "编码助手",
        workspace: "D:/my-claw/workspace-coding",
        model: "anthropic/claude-opus-4-6",
      },
    ],
  },
}
```

要点：
- **模型 ID 格式**：`provider/modelId`（首个 `/` 切分），例：`openrouter/moonshotai/kimi-k2`
- **多 agent**：一个 `list[]` 一份独立人格 + workspace + 会话存储
- **路由**：渠道接入用 `bindings`（见 `docs/concepts/multi-agent.md`）

---

## 3. 角色定义与系统提示

**结论：系统提示词不写在配置里，也不写代码。直接编辑 workspace 里的 6 个 markdown。**

OpenClaw 在每个新会话首轮，把这些文件原文注入 system prompt 的 *Project Context* 段：

| 文件 | 装什么 |
| --- | --- |
| `AGENTS.md` | 操作指令、任务规则、记忆使用方式（系统提示主体） |
| `SOUL.md` | 人格、语气、边界、回复风格 |
| `IDENTITY.md` | agent 名字、emoji、自我形象 |
| `USER.md` | 用户身份、想被怎么称呼 |
| `TOOLS.md` | 本地工具使用约定（仅说明，不开关工具） |
| `BOOTSTRAP.md` | 一次性首启仪式，跑完可删 |

写法：纯 markdown，没有 frontmatter 要求；空文件会被跳过；过长会被截断（受 `bootstrapMaxChars` / `bootstrapTotalMaxChars` 控制）。  
`openclaw setup --workspace D:/my-claw/workspace` 会生成空模板，再去填内容即可。

参考：`docs/concepts/agent.md` § Bootstrap files、`docs/concepts/soul.md`。

---

## 4. 自定义 Skill

Skill = 一个目录 + 一个带 frontmatter 的 `SKILL.md`。**加载优先级（高 → 低）**：

1. `<workspace>/skills/<name>/SKILL.md`
2. `<workspace>/.agents/skills/<name>/SKILL.md`
3. `~/.agents/skills/<name>/SKILL.md`（跨 agent，本机共享）
4. `~/.openclaw/skills/<name>/SKILL.md`（全局 managed）
5. `skills.load.extraDirs` 列出的目录（最低）

最简示例 `D:/my-claw/skills/my-search/SKILL.md`：

```markdown
---
name: my-search
description: 在公司内部 wiki 检索关键词
metadata: { "openclaw": { "requires": { "bins": ["wiki-cli"], "env": ["WIKI_TOKEN"] } } }
---
当用户要求检索内部资料时：
1. 调用 `wiki-cli search {query}`（通过 exec 工具）
2. 返回前 5 条结果（标题 + URL）
```

配置注册外置 skill 目录与开关：

```json5
{
  skills: {
    load: {
      extraDirs: ["D:/my-claw/skills"],
      watch: true,                 // 文件变更热重载
      watchDebounceMs: 250,
    },
    entries: {
      "my-search": {
        enabled: true,
        env: { WIKI_TOKEN: "xxx" }, // 仅注入到本次 agent run
      },
    },
  },
}
```

也可以 `openclaw skills install ./D:/my-claw/skills/my-search --as my-search` 一键拷到工作区。

参考：`docs/tools/skills.md`。

---

## 5. 自定义工具（Tool）

OpenClaw 的工具必须通过插件 `api.registerTool()` 注册。**不改源码 = 写独立插件包**，走 `openclaw plugins install` 装进来。

`D:/my-claw/plugins/my-tools/openclaw.plugin.json`：

```json
{
  "id": "my-tools",
  "name": "My Tools",
  "version": "1.0.0",
  "contracts": { "tools": ["my_query", "my_run"] },
  "toolMetadata": {
    "my_run": { "optional": true }
  }
}
```

`D:/my-claw/plugins/my-tools/index.ts`：

```typescript
import { Type } from "typebox";
import { definePluginEntry } from "openclaw/plugin-sdk/plugin-entry";

export default definePluginEntry({
  id: "my-tools",
  name: "My Tools",
  register(api) {
    api.registerTool({
      name: "my_query",
      description: "查询内部接口",
      parameters: Type.Object({ q: Type.String() }),
      async execute(_id, p) {
        const r = await fetch(`https://internal/api?q=${encodeURIComponent(p.q)}`);
        return { content: [{ type: "text", text: await r.text() }] };
      },
    });

    api.registerTool(
      { name: "my_run", description: "...", parameters: Type.Object({}), async execute() { /*…*/ } },
      { optional: true },         // 默认不暴露，需 tools.allow 开
    );
  },
});
```

安装与启用：

```bash
# 本地路径直装
openclaw plugins install file:D:/my-claw/plugins/my-tools

# 或发布到 ClawHub 后
openclaw plugins install clawhub:your-org/my-tools
```

```json5
{ tools: { allow: ["my_run"] } }   // 启用 optional 工具
```

> **轻量替代**：如果"工具"只是包一个 CLI，写个 Skill + `command-dispatch: tool` + `command-tool: exec` 转发就够了，不用做插件。  
> 工具命名不能与核心工具撞名；撞名会被插件诊断丢弃。

参考：`docs/plugins/building-plugins.md` § Registering tools、`docs/plugins/manifest.md`。

---

## 6. 工作流

四种机制，按复杂度递增，全部不改源码：

### 6.1 Standing Orders（最简单）

直接写进 `<workspace>/AGENTS.md`，会随每会话注入：

```markdown
## Program: 每日早报
**Authority:** 拉取邮件、整理、发到 Slack
**Trigger:** 每天 09:00（由 cron 强制触发）
**Approval gate:** 数据异常 >2σ 时停下问人
**Escalation:** 数据源不可用时上报

### Steps
1. 调 `mail_fetch` 拉昨日未读
2. 调 `summarize` 出 5 条要点
3. 调 `slack_send` 发到 #morning
```

### 6.2 Cron Jobs（定时触发）

```bash
openclaw cron add \
  --name daily-report \
  --schedule "0 9 * * *" \
  --prompt "执行 standing order: 每日早报"
```

落到 `~/.openclaw/cron.json`，详见 `docs/automation/cron-jobs.md`。

### 6.3 Hooks（事件驱动）

`D:/my-claw/hooks/session-snapshot/HOOK.md`：

```markdown
---
name: session-snapshot
events: [command:new, session:compact:after]
---
```

`handler.ts` 写副作用逻辑（见 `docs/automation/hooks.md`）。

注册：

```json5
{
  hooks: {
    enabled: true,
    extraDirs: ["D:/my-claw/hooks"],
    entries: { "session-snapshot": { enabled: true } },
  },
}
```

可监听事件包含：`command:new` `command:reset` `command:stop` `session:compact:before/after` `agent:bootstrap` `gateway:startup` `message:received` `message:sent` 等。

### 6.4 Task Flow（多步编排）

适合一条业务流要走多 agent / 多工具的场景。yaml/markdown 描述节点和依赖，由 agent 自主推进，详见 `docs/automation/taskflow.md`。

---

## 7. 落地步骤

1. `mkdir D:/my-claw && cd D:/my-claw`
2. `openclaw setup --workspace D:/my-claw/workspace`（生成 6 个模板文件）
3. 编辑 `workspace/AGENTS.md` `SOUL.md` `IDENTITY.md` `USER.md` 定义角色与系统提示
4. 在 `~/.openclaw/openclaw.json` 写 `agents.defaults` + `agents.list`，指向 workspace
5. 自定义 skill 丢到 `workspace/skills/` 或 `D:/my-claw/skills/` + 配 `skills.load.extraDirs`
6. 自定义工具：`plugins/my-tools/` 写好后 `openclaw plugins install file:./plugins/my-tools`
7. 工作流：standing orders 写 `AGENTS.md`；定时 `openclaw cron add`；事件放 `hooks/` 目录
8. `openclaw gateway restart` → 浏览器开 `http://127.0.0.1:18789/chat` 验证
9. `D:/my-claw/` 整个用私有 git 仓库备份（`.gitignore` 排掉 token / API key）

---

## 8. 定制能力速查

| 想做的事 | 不改源码的做法 |
| --- | --- |
| 改 system prompt | 编辑 `workspace/AGENTS.md`、`SOUL.md` |
| 加 agent | `agents.list[]` 增一项 + 新 workspace 目录 |
| 改模型 | `agents.list[].model = "provider/modelId"` |
| 加新 Provider | 装对应 provider 插件（多数已内置） |
| 加 Skill | 放 `workspace/skills/` 或配 `skills.load.extraDirs` |
| 加 Tool | 独立插件包 + `api.registerTool` + `plugins install` |
| 加事件钩子 | `hooks/` 目录 + `hooks.extraDirs` |
| 加 RPC / HTTP 端点 | 插件用 `contracts.gatewayMethodDispatch` 注册 |
| 加 MCP server | acpx 或对应渠道插件，配置侧接入 |
| 加定时任务 | `openclaw cron add` 或 standing order + cron |
| 持久化偏好 | `workspace/MEMORY.md` + `memory/<date>.md` |
| 改记忆后端 | `memory.backend` 切 qmd / lancedb / 自建插件 |

---

## 9. 不要碰源码的边界

唯一可能想动源码但其实不必动的场景：改 Pi runtime 或 auto-reply 管线行为。这部分用 hooks 足够覆盖：

- 想在压缩前后做事 → `session:compact:before` / `session:compact:after`
- 想拦截入站消息 → `message:received` / `message:preprocessed`
- 想改首轮 bootstrap → `agent:bootstrap`
- 想接管出站 → `message:sent`
- 想做 prompt 重写 / 工具拦截 → 写 plugin 用 `api.on(...)`（typed plugin hooks）

只有当这些都解决不了时，再考虑给 OpenClaw 上游提 PR，而不是 fork 改本地源码。

---

## 10. 参考文档（项目内）

| 主题 | 路径 |
| --- | --- |
| Agent 运行时 / bootstrap | `docs/concepts/agent.md` |
| Workspace 完整布局 | `docs/concepts/agent-workspace.md` |
| 多 agent 路由 | `docs/concepts/multi-agent.md` |
| SOUL.md 写法 | `docs/concepts/soul.md` |
| Skill 加载与白名单 | `docs/tools/skills.md` |
| 写自定义工具插件 | `docs/plugins/building-plugins.md` |
| 插件 manifest | `docs/plugins/manifest.md` |
| Standing orders | `docs/automation/standing-orders.md` |
| Cron jobs | `docs/automation/cron-jobs.md` |
| 事件 hooks | `docs/automation/hooks.md` |
| Task flow | `docs/automation/taskflow.md` |
| 内部源码导览（debug 用） | `adoc/架构设计文档.md` |

---

## 11. 状态目录布局（`OPENCLAW_STATE_DIR`）

OpenClaw 默认把所有运行时状态放在 `~/.openclaw/`。当 gateway 用
`OPENCLAW_STATE_DIR=<path>`（以及/或 `OPENCLAW_CONFIG_PATH`）启动时——比如
本机的 systemd unit `openclaw-gateway-dev.service`，它把状态目录指到了
`/root/.openclaw-dev/`——下面所有文件就改放到那个路径下，目录结构不变。

```
<state-dir>/
├── openclaw.json                # 主配置（gateway / agents / meta / session / tools / models / wizard）
├── openclaw.json.bak            # 上一次写入前的滚动备份（最近一份）
├── openclaw.json.bak.1..3       # 更早的滚动备份，下标越大越旧
├── openclaw.json.last-good      # 健康监视器认证过的"最后一份好配置"
├── update-check.json            # 上次 `openclaw update` 检查的时间戳
│
├── identity/
│   └── device.json              # 本 gateway 的 Ed25519 deviceId + 公私钥（用于签名 / 自我标识）
│
├── devices/
│   ├── paired.json              # 已配对客户端（Control UI、operator 等）的 token / role / scopes
│   └── pending.json             # 待审批的配对请求
│
├── agents/<agent-name>/         # 每个 agent 一个子树（如 `dev`、`main`）
│   ├── agent/
│   │   ├── models.json          # 该 agent 的模型清单（provider / baseUrl / api / cost）
│   │   └── codex-home/          # 仅 codex 风格 agent 才有，相当于该 agent 的 HOME
│   │       ├── installation_id          # codex 安装 ID
│   │       ├── .personality_migration   # 老版 personality 数据的迁移标记
│   │       ├── state_5.sqlite (+ -wal, -shm)  # codex 主状态库（SQLite WAL 模式）
│   │       ├── logs_2.sqlite                  # codex 日志库
│   │       ├── memories/                       # codex 长期记忆条目
│   │       ├── skills/                         # codex skill 定义
│   │       └── tmp/                            # 临时文件（如 `arg0`）
│   └── sessions/
│       ├── <uuid>.jsonl                        # 对话回合记录（用户可见层）
│       ├── <uuid>.trajectory.jsonl             # 完整 trace（含工具调用、思考），用于回放/调试
│       ├── <uuid>.trajectory-path.json         # 指向 trajectory 文件的小指针
│       ├── <uuid>.jsonl.reset.<ts>.jsonl       # session 被 reset 时的归档
│       ├── sessions.json                       # 该 agent 的 session 索引
│       └── .usage-cost-cache.json              # 各 session 的 token / 费用计算缓存
│
├── memory/
│   └── <profile>.sqlite         # 跨 session 的长期记忆库
│
├── tasks/
│   └── runs.sqlite (+ -wal, -shm)   # 后台任务 / 运行历史（SQLite WAL 模式）
│
├── plugin-skills/               # 全是软链：把插件提供的 skill 暴露给 gateway
│   ├── acp-router            -> <repo>/dist/extensions/acpx/skills/acp-router
│   ├── browser-automation    -> <repo>/dist/extensions/browser/skills/browser-automation
│   ├── qqbot-channel         -> <repo>/extensions/qqbot/skills/qqbot-channel
│   ├── qqbot-media           -> <repo>/extensions/qqbot/skills/qqbot-media
│   └── qqbot-remind          -> <repo>/extensions/qqbot/skills/qqbot-remind
│
├── logs/
│   ├── config-audit.jsonl       # 每次写 `openclaw.json` 的审计行（pid / argv / 前后 hash）
│   └── config-health.json       # 健康监视器对每个 config 文件的视图（last-known-good 等）
│
└── tui/
    └── last-session.json        # TUI 客户端上次连到的 sessionKey，下次启动用来 resume
```

要点：

- `*.sqlite` 都是 SQLite WAL 模式的库，旁边的 `-wal` 和 `-shm` 不能单独删——
  单独删任意一个都会损坏数据库。
- `plugin-skills/` 里全是软链，源在仓库的 `extensions/*` 或者构建产物
  `dist/extensions/*`。改 skill 直接改源文件即可，重启 gateway 生效，不用拷贝。
- `openclaw.json.bak[.N]` 是机械的滚动备份（每次写都会推一格），
  `openclaw.json.last-good` 则要等健康监视器验证通过才会被提升。恢复时优先用
  后者，更安全。
- `agents/` 下面的子目录名是 **agent 名**（如 `dev`、`main`），不是 gateway
  profile。gateway profile 由 `OPENCLAW_PROFILE` 决定，它影响的是挂哪个 state
  目录，不是这里的子目录命名。
