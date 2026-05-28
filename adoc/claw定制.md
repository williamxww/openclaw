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
| 不依赖向导 | 不跑 `openclaw onboard` / `openclaw setup` / `openclaw configure`，所有产物（配置 / workspace / auth-profiles / 插件）首启前**手动**就位 |
| 严格校验 | gateway 启动会用 schema 校验 `openclaw.json`，未知字段或类型错都会拒启动；首启前先 `openclaw config schema` 对照、出错用 `openclaw doctor` 排查 |
| 先定义后启动 | gateway 第一次起来之前必须备好：配置 + workspace md + 模型 auth + 已装插件；gateway 只是把这堆产物加载起来 |

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
      // workspace 已手写好 5 个 md，禁止 gateway 首启自动播种模板
      skipBootstrap: true,
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

## 7. 落地步骤（不用向导，先定义后启动）

> 顺序原则：**所有产物在 gateway 第一次启动之前手动到位**。gateway 启动只是把它们加载起来——schema 校验不通过会直接拒启动。

### 阶段 A：首启**之前**，纯文件操作（gateway 不要起）

1. **建仓库骨架**
   ```bash
   mkdir -p D:/my-claw/{workspace,workspace/skills,skills,plugins,hooks,workflows}
   cd D:/my-claw && git init
   ```
   `.gitignore` 至少排掉：`*.token`、`*.key`、`auth-profiles*.json`、`.env*`。

2. **手写 workspace 的 5 个 md**（别跑 `openclaw setup`，那是简化向导）
   在 `D:/my-claw/workspace/` 下逐个新建：
   - `AGENTS.md` — 操作指令、任务规则、记忆使用方式
   - `SOUL.md` — 人格、语气、边界
   - `IDENTITY.md` — agent 名字 / emoji / 自我形象
   - `USER.md` — 用户身份与称呼
   - `TOOLS.md` — 工具使用约定（仅说明）
   不要建 `BOOTSTRAP.md`——只要任一其他 bootstrap 文件存在，OpenClaw 就不会再生成它。

3. **手写 `~/.openclaw/openclaw.json`**
   按 §2 / §4 / §5 拼出 `agents.defaults` + `agents.list[]` + `skills.load.extraDirs` + `tools.allow` + 必要的 `hooks` / `plugins.entries`。
   关键开关：`agents.defaults.skipBootstrap: true`，禁止首启自动播种模板，确保你的手写 md 不会被覆盖也不会被 ritual 注入额外指令。
   写完先 dry-check：
   ```bash
   openclaw config schema > /tmp/schema.json   # 拉 schema 对照
   openclaw doctor                              # 离线静态检查
   ```

4. **手写模型 auth**（不依赖 `onboard` / `channels login`）
   每个 agent 对应一份：
   ```
   ~/.openclaw/agents/<agentId>/agent/auth-profiles.json
   ```
   只放 `api_key` / `token` 这种**可移植的静态凭据**就行，OAuth 走环境变量或 secret ref。
   敏感值优先用 secret ref（`env:` / `file:` / `exec:`），别裸写到 JSON。

5. **装自定义插件**（gateway 不在跑也能装；插件磁盘就位 = 首启时被注册）
   ```bash
   openclaw plugins install file:D:/my-claw/plugins/my-tools
   ```
   再在 `openclaw.json` 里：`tools.allow: ["my_run"]`（如果是 optional 工具）。

### 阶段 B：第一次启动 gateway

6. **首次启动**（不是 restart——此前没东西可重启）
   ```bash
   openclaw gateway start
   ```
   起来后立刻验证：
   ```bash
   openclaw gateway status
   openclaw health
   ```
   起不来：`openclaw doctor` 看 schema / 路径 / 权限错；不要用 `--fix` 直接覆盖你的手写配置，先看清差异。

7. **进 UI 跑一句通路**
   浏览器打开 `http://127.0.0.1:18789/chat`，发一条话验证模型可达、bootstrap md 已被注入到 system prompt。

### 阶段 C：起来**之后**才做的事（多数热改，无需重启）

8. **调 skills / 改 workspace md / 加 cron**——全是热改：
   - skills：开 `skills.load.watch: true`，编辑保存即重载
   - workspace md：开新 session 即生效（同一 session 不重读）
   - cron：`openclaw cron add ...` 直接落 `~/.openclaw/cron.json`

9. **加 / 换插件，新增 agent，加 hooks**——这些要 `openclaw gateway restart`（详见 §8.2）。

10. **整仓库走私有 git 备份**：`D:/my-claw/` 自治，`~/.openclaw/openclaw.json` 用软链或部署脚本同步过去。auth-profiles / token 留在 `~/.openclaw/`，**不**进这个仓库。

---

## 8. 热改 vs 必须 restart

写好之后改东西时，先按这张表判断要不要 `openclaw gateway restart`，避免无谓重启或漏改没生效。

### 8.1 热改即生效（不用动 gateway）

| 改动 | 触发时机 | 备注 |
| --- | --- | --- |
| `workspace/*.md`（AGENTS / SOUL / IDENTITY / USER / TOOLS） | **新开 session** 时注入 | 同一 session 不会重读；要立即看效果就开新 session |
| `workspace/skills/**` 或 `extraDirs` 下的 skill | 文件变更即时重载 | 需 `skills.load.watch: true`；改 frontmatter 也算 |
| `~/.openclaw/openclaw.json` 大多数字段 | gateway 监听该文件，**热 reload** | schema 校验失败 → 跳过 reload，保留旧配置不崩；`doctor` 排查 |
| `openclaw cron add/rm/ls` | 直接落 `~/.openclaw/cron.json` | 调度器实时拾取 |
| Standing orders（写在 `AGENTS.md`） | 同 workspace md 规则 | 新 session 生效 |
| `tools.allow` 增减已注册工具 | 配置 reload 后下次工具列举生效 | 注意：只能开关**已注册**的工具；新工具属于装插件 |
| `skills.entries.<name>.enabled` / `env` | 配置 reload 即时生效 | 切 skill 白名单不需要重启 |

### 8.2 必须 `openclaw gateway restart`

| 改动 | 原因 |
| --- | --- |
| 装 / 卸 / 升级 / 改名插件 | `registerTool` / `contracts` / RPC 端点在 plugin load 阶段才跑 |
| `agents.list[]` 新增 / 删除 agent | 要新建 `agentDir` / session store / auth-profiles 路径并完成路由绑定 |
| 新增 hook（`hooks.extraDirs` 加目录、`hooks.entries.<x>.enabled` 由 false 转 true） | hook 注册表只在启动时扫一次；既有 hook 的 handler 代码改动同样要重启 |
| 改 gateway 监听端口 / `controlUi.root` / 其它 boot-time 字段 | 这些在 socket bind / 静态资源挂载时一次性读 |
| 切 `OPENCLAW_STATE_DIR` / `OPENCLAW_CONFIG_PATH` / `OPENCLAW_PROFILE` | 状态目录是进程级常量 |
| 改 `memory.backend`（如 qmd ↔ lancedb） | 后端连接在启动时建立 |
| device key / identity 改动 | gateway 启动时一次性加载 Ed25519 keypair |

### 8.3 介于两者之间

- **`agents.list[].model` 改模型**：下一次 agent run 自动用新模型，不需要 restart；但若同时切了 provider 而 auth-profiles 还没就位，会运行时报错——把 auth 准备好再改更稳。
- **`auth-profiles.json` 改 token / key**：多数路径会重读文件，但部分长连 provider 缓存 client 实例；最稳是 restart。
- **改插件源码（已装的本地插件）**：dev 模式下 `pnpm gateway:watch` 自动重载；生产用 `gateway restart`。

经验法则：**只动数据**（md / json 的字段值 / cron 条目）多半热改；**改结构**（加 agent、加 hook、加插件、改端口）一律 restart。

---

## 9. 定制能力速查

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

## 10. 不要碰源码的边界

唯一可能想动源码但其实不必动的场景：改 Pi runtime 或 auto-reply 管线行为。这部分用 hooks 足够覆盖：

- 想在压缩前后做事 → `session:compact:before` / `session:compact:after`
- 想拦截入站消息 → `message:received` / `message:preprocessed`
- 想改首轮 bootstrap → `agent:bootstrap`
- 想接管出站 → `message:sent`
- 想做 prompt 重写 / 工具拦截 → 写 plugin 用 `api.on(...)`（typed plugin hooks）

只有当这些都解决不了时，再考虑给 OpenClaw 上游提 PR，而不是 fork 改本地源码。

---

## 11. 参考文档（项目内）

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

## 12. 状态目录布局（`/root/.openclaw-dev/`）

本机由 systemd unit `openclaw-gateway-dev.service` 启动 gateway，
通过环境变量把状态目录钉死在 `/root/.openclaw-dev/`：

```
Environment=OPENCLAW_STATE_DIR=/root/.openclaw-dev
Environment=OPENCLAW_CONFIG_PATH=/root/.openclaw-dev/openclaw.json
Environment=OPENCLAW_PROFILE=dev
```

OpenClaw 默认状态目录是 `~/.openclaw/`，dev profile 用 `-dev` 后缀做隔离。
这两套目录结构完全相同，下面以 `/root/.openclaw-dev/` 为例：

```
/root/.openclaw-dev/
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
├── agents/<agent-name>/         # 每个 agent 一个子树（本机有 `dev`、`main`）
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
│   └── dev.sqlite               # 跨 session 的长期记忆库（按 profile 命名）
│
├── tasks/
│   └── runs.sqlite (+ -wal, -shm)   # 后台任务 / 运行历史（SQLite WAL 模式）
│
├── plugin-skills/               # 全是软链：把插件提供的 skill 暴露给 gateway
│   ├── acp-router            -> /data/server/oschina/openclaw/dist/extensions/acpx/skills/acp-router
│   ├── browser-automation    -> /data/server/oschina/openclaw/dist/extensions/browser/skills/browser-automation
│   ├── qqbot-channel         -> /data/server/oschina/openclaw/extensions/qqbot/skills/qqbot-channel
│   ├── qqbot-media           -> /data/server/oschina/openclaw/extensions/qqbot/skills/qqbot-media
│   └── qqbot-remind          -> /data/server/oschina/openclaw/extensions/qqbot/skills/qqbot-remind
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
