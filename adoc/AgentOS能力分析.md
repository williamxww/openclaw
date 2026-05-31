# OpenClaw AgentOS 核心能力分析

> 基于源码结构、架构设计文档与行业参考，系统梳理 OpenClaw 作为 AgentOS 的核心能力。

---

## 什么是 AgentOS

AgentOS（Agent Operating System）是一种专为 AI Agent 设计的运行时基础设施，类比传统操作系统对进程、内存、I/O 的管理，AgentOS 负责管理 Agent 的上下文、记忆、工具调用、多 Agent 协作、调度与安全边界。

学术界（AIOS, Rutgers 2025）和工业界（MindStudio, AgentX 等）对 AgentOS 的核心层次有基本共识：

| 层次 | 职责 |
|------|------|
| Kernel / 运行时 | Agent 主循环、工具执行、上下文管理 |
| 记忆系统 | 短期/长期记忆、检索、压缩 |
| 工具层 | 文件、网络、代码执行、外部 API |
| 编排层 | 多 Agent 协作、任务调度、生命周期 |
| 渠道/接入层 | 多端接入、消息路由、协议适配 |
| 安全与治理 | 权限、沙箱、审计、策略 |

OpenClaw 在上述每个层次都有对应实现，以下逐层展开。

---

## 目录

1. [嵌入式 Agent 运行时（Pi Runner）](#1-嵌入式-agent-运行时pi-runner)
2. [多模型提供者与 Harness 路由](#2-多模型提供者与-harness-路由)
3. [上下文引擎与自动压缩](#3-上下文引擎与自动压缩)
4. [持久化记忆系统](#4-持久化记忆系统)
5. [Skill 能力注入](#5-skill-能力注入)
6. [工具执行层](#6-工具执行层)
7. [多 Agent 编排（子 Agent 系统）](#7-多-agent-编排子-agent-系统)
8. [定时任务与自主调度（Cron）](#8-定时任务与自主调度cron)
9. [TaskFlow 任务流注册表](#9-taskflow-任务流注册表)
10. [Hook 事件系统](#10-hook-事件系统)
11. [多渠道接入层](#11-多渠道接入层)
12. [MCP 协议集成](#12-mcp-协议集成)
13. [ACP 协议支持](#13-acp-协议支持)
14. [沙箱执行环境](#14-沙箱执行环境)
15. [安全与审计体系](#15-安全与审计体系)
16. [插件化架构（Plugin SDK）](#16-插件化架构plugin-sdk)
17. [OpenAI 兼容 HTTP 网关](#17-openai-兼容-http-网关)
18. [轨迹追踪与可观测性](#18-轨迹追踪与可观测性)
19. [能力全景图](#19-能力全景图)

---

## 1. 嵌入式 Agent 运行时（Pi Runner）

**对应 AgentOS 层次：Kernel / 运行时**

Pi Runner 是 OpenClaw 的 Agent 执行内核，所有 Agent 对话最终都汇入这里完成模型调用、工具执行和上下文管理。

### 两条入口路径，同一个内核

```
webchat / 渠道消息
  → auto-reply 管线（src/auto-reply/）
  → runAgentTurnWithFallback
  → runEmbeddedPiAgent          ← 同一个 Pi 内核
                                ↑
CLI / agent RPC / OpenAI HTTP
  → agentCommandInternal（src/agents/agent-command.ts）
  → runEmbeddedPiAgent
```

两条路径的分工：auto-reply 管线负责会话门控（要不要回、群聊去抖、freshness 检查）；`agent-command.ts` 负责命令式调用。两者最终都通过 `runEmbeddedPiAgent`（`src/agents/pi-embedded.ts`）进入同一个 Pi 运行时。

### Run 生命周期状态机

```
pending → active → streaming → compacting → completed
                                           ↘ aborted
```

关键文件：`src/agents/pi-embedded-runner/runs.ts`，提供 Run 的入队、中止、等待、强制清理等完整生命周期管理。

### 核心能力

- **流式输出**：模型响应逐 token 推送到 WebSocket 客户端
- **Attempt 循环**：内置重试机制，失败时自动切换模型或 Auth Profile
- **Lane 超时**：每个 Run 有独立超时（含 30s 宽限期），防止卡死
- **队列优先级**：根据触发类型（用户主动 vs 定时任务）分配队列优先级
- **空闲超时检测**：`hasCompletedModelProgressForIdleBreaker` 检测模型是否有进展

---

## 2. 多模型提供者与 Harness 路由

**对应 AgentOS 层次：Kernel / 运行时**

OpenClaw 支持数十个 LLM 提供者，通过 Harness 路由机制在运行时动态选择执行后端。

### 支持的提供者（extensions/ 目录）

| 类别 | 提供者 |
|------|--------|
| 主流云端 | OpenAI、Anthropic、Google Gemini、Amazon Bedrock、Azure、Microsoft Foundry |
| 国内模型 | 阿里 Qwen、DeepSeek、MiniMax、Moonshot、百度千帆、字节火山、腾讯、MiniMax |
| 开源/本地 | Ollama、LM Studio、vLLM、SGLang、Groq、Together、Fireworks |
| 路由/代理 | OpenRouter、LiteLLM、Cloudflare AI Gateway、Vercel AI Gateway |
| 专用 | GitHub Copilot、xAI、Chutes、Arcee、Cerebras、Perplexity |

### Harness 路由策略

`resolveAgentHarnessPolicy()` 根据 provider + modelId + agentId 决定走哪条执行路径：

- **Embedded Pi 路径**（默认）：内置运行时，直接调 LLM API
- **CLI Agent 路径**：调用外部 CLI（claude、codex 等），适合需要外部工具链的场景

### 模型降级与 Auth Profile 轮换

- `model-fallback.ts`：主模型失败时自动降级到备用模型
- `auth-profiles.ts`：多个 API Key 轮换，支持冷却期自动恢复
- `api-key-rotation.ts`：API Key 轮换策略

---

## 3. 上下文引擎与自动压缩

**对应 AgentOS 层次：Kernel / 上下文管理**

上下文管理是 AgentOS 的核心挑战之一。OpenClaw 通过可插拔的上下文引擎和自动压缩机制解决长对话的 Token 溢出问题。

### 可插拔上下文引擎

`src/context-engine/registry.ts` 提供引擎注册表，支持第三方通过 Plugin SDK 注册自定义上下文引擎：

```typescript
registerContextEngine(engineId, factory)  // 公开 SDK 入口
resolveContextEngine(sessionKey, ...)     // 主解析函数，含降级逻辑
```

引擎输出标准化的 `AssembleResult`：

```typescript
{
  messages: Message[]           // 有序消息列表
  estimatedTokens: number       // Token 估算
  systemPromptAddition?: string // 可选系统提示追加
  projectionMode: "per-turn" | "thread-bootstrap"
}
```

### 自动上下文压缩（Compaction）

当上下文接近模型窗口上限时，自动触发压缩流程（`src/agents/pi-embedded-runner/compact.ts`）：

```
检测到上下文溢出
  → prepareCompactionSessionAgent()   # 准备压缩专用 Agent 配置
  → resolveCompactionProviderStream() # 选择压缩用的 Provider
  → 调用模型生成摘要
  → 旋转 Transcript（保留摘要，丢弃旧消息）
  → 触发 compaction-hooks 后置副作用
```

压缩有独立的安全超时（`compaction-safety-timeout.ts`），防止压缩本身卡死整个 Run。

---

## 4. 持久化记忆系统

**对应 AgentOS 层次：记忆系统**

OpenClaw 实现了多层次的持久化记忆，让 Agent 在跨会话、跨重启后仍能保持连续性。

### 记忆存储结构

```
~/.openclaw/agents/<agentId>/
├── memory/
│   ├── MEMORY.md              # 核心记忆索引（结构化 Markdown）
│   ├── daily-notes/           # 每日笔记（按日期归档）
│   └── dreaming/              # Dream 报告（后台异步生成的记忆摘要）
└── sessions/                  # 会话 Transcript 持久化
```

### 记忆制品类型

| 类型 | 说明 |
|------|------|
| `memory-md` | 核心记忆文件，Agent 的"长期记忆" |
| `daily-note` | 每日笔记，记录当天的重要事件 |
| `dream-report` | Dream 报告，后台异步对历史记忆做摘要整合 |
| `event-log` | 结构化事件日志（JSON），用于精确检索 |

### 记忆写入流程

```
Agent 执行结束
  → memory-host-events.ts    # 记录结构化事件日志
  → memory-host-markdown.ts  # 更新 MEMORY.md
  → memory-host-search.ts    # 更新搜索索引
```

### 记忆检索

`src/agents/memory-search.ts` 提供语义检索能力，Agent 可通过 `memory_search` / `memory_get` 工具在执行时主动查询历史记忆。

### 向量记忆扩展

`extensions/memory-lancedb/` 提供基于 LanceDB 的向量记忆后端，支持语义相似度检索，适合大规模记忆场景。

---

## 5. Skill 能力注入

**对应 AgentOS 层次：编排层 / 能力管理**

Skill 是 OpenClaw 的能力单元，类似传统 OS 中的"驱动程序"——它们描述 Agent 能做什么，并以结构化文本注入模型的系统提示。

### Skill 加载来源（6 类）

`src/agents/skills/workspace.ts:loadSkillEntries` 从以下来源聚合 Skill：

1. **捆绑 Skill（bundled）**：随 OpenClaw 核心发布，始终可用
2. **额外 Skill（extra）**：用户手动添加的补充 Skill
3. **托管 Skill（managed）**：通过 ClawHub 安装的官方 Skill 包
4. **个人 Agent Skill**：特定 Agent 的私有 Skill
5. **项目 Agent Skill**：项目级别的 Skill（随代码库分发）
6. **工作区来源 Skill**：从工作区目录动态发现

### Skill 快照与提示注入

```typescript
type SkillSnapshot = {
  prompt: string           // 注入模型系统提示的技能描述文本
  skills: SkillEntry[]     // 原始技能条目
  resolvedSkills: ResolvedSkill[]  // 解析后的技能（含环境覆盖）
}
```

当 Skill 数量超过字符限制时，自动降级为紧凑格式（仅名称+位置），保证系统提示不溢出。

### Skill 安装与同步

- `skills-install.ts`：从 ClawHub 或本地 tar 包安装 Skill
- `syncSkillsToWorkspace`：将 Skill 同步到目标工作区
- `filterWorkspaceSkillEntries`：按配置过滤（eligibility、skillFilter）

---

## 6. 工具执行层

**对应 AgentOS 层次：工具层**

工具是 Agent 与外部世界交互的唯一接口。OpenClaw 提供了一套完整的工具执行框架，包含工具目录、策略引擎、循环检测和结果保护。

### 核心工具分区

`src/agents/tool-catalog.ts` 定义了 4 个工具 Profile 和 9 个工具分区：

| 分区 | 工具 | 说明 |
|------|------|------|
| Files | read, write, edit, apply_patch | 文件系统操作 |
| Runtime | exec, process, code_execution | 代码/命令执行 |
| Web | web_search, web_fetch, x_search | 网络访问 |
| Memory | memory_search, memory_get | 记忆检索 |
| Sessions | sessions_list, sessions_history, sessions_send | 会话管理 |
| Agents | sessions_spawn, sessions_yield, subagents | 子 Agent 控制 |
| UI | session_status | 状态展示 |
| Messaging | 渠道消息工具 | 跨渠道发消息 |
| Automation | 自动化工具 | 系统自动化 |

### 工具执行管道

```
模型返回 Tool Call
  → tool-name-allowlist.ts      # 白名单校验
  → tool-policy-pipeline.ts     # 策略管道（allow/deny/approve）
  → tool-catalog.ts             # 路由到处理器
  → 工具执行
  → tool-result-truncation.ts   # 截断过大结果
  → tool-result-context-guard.ts # 防止上下文溢出
  → 返回结果给模型
```

### 工具安全机制

- **工具循环检测**：`tool-loop-detection.ts` 检测 Agent 陷入无限工具调用循环
- **工具变更追踪**：`tool-mutation.ts` 追踪工具对系统状态的变更
- **执行审批**：`bash-tools.exec-approval-request.ts` 支持危险命令的人工审批流程
- **工具策略**：4 种 Profile（minimal/coding/messaging/full）控制工具可用范围

---

## 7. 多 Agent 编排（子 Agent 系统）

**对应 AgentOS 层次：编排层**

这是 OpenClaw 作为 AgentOS 最具代表性的能力之一——支持父 Agent 动态 Spawn 子 Agent，形成树状协作结构。

### 子 Agent 生命周期

```
父 Agent 调用 sessions_spawn 工具
  → subagent-spawn.ts
      ├─ 校验 Spawn 策略 & 深度限制
      ├─ buildDirectChildSessionPatch()    # 构建子 Session 配置
      ├─ prepareSubagentSessionContext()   # Fork/隔离上下文
      └─ prepareContextEngineSubagentSpawn()
  → subagent-registry.ts
      ├─ 注册子 Agent Run
      ├─ 持久化到磁盘
      └─ 启动子 Agent 执行（同主循环）
  → 子 Agent 执行完成
  → subagent-announce.ts  # 向父 Agent 通知结果
  → 父 Agent 通过 sessions_yield 等待并继续
```

### 关键设计

| 特性 | 实现 |
|------|------|
| 深度限制 | `subagent-depth.ts`，防止无限嵌套 |
| 孤儿恢复 | `subagent-orphan-recovery.ts`，进程重启后恢复中断的子 Agent |
| 并发控制 | 父 Agent 可同时 Spawn 多个子 Agent，通过注册表追踪 |
| 上下文隔离 | 子 Agent 有独立的 Session 和上下文，不污染父 Agent |
| 结果投递 | `subagent-announce-delivery.ts`，保证结果幂等投递 |

### 执行契约（Execution Contract）

不同模型使用不同执行契约，`execution-contract.ts` 根据 provider + modelId 决定：

- `"default"`：标准 Agent 执行流程
- `"strict-agentic"`：GPT-5 系列专用，无停滞完成门控、不完整轮次恢复

### ACP 协议（Agent Communication Protocol）

`src/acp/` 实现了标准 ACP 协议（`@agentclientprotocol/sdk`），支持：
- 跨进程 Agent 通信
- 会话绑定与权限中继
- 事件账本（event-ledger）追踪 Agent 间消息
- 速率限制与会话创建控制

---

## 8. 定时任务与自主调度（Cron）

**对应 AgentOS 层次：编排层 / 调度**

OpenClaw 内置完整的 Cron 调度系统，让 Agent 能够自主执行定时任务，无需用户主动触发。

### 核心能力

`src/cron/` 提供：

- **标准 Cron 表达式**：支持 `every`（间隔）和 `at`（定时）两种模式
- **隔离 Agent 执行**：每个 Cron 任务在独立的 Agent 实例中运行（`isolated-agent.ts`）
- **失败通知**：任务失败时自动通知（`delivery.failure-notify.ts`）
- **心跳策略**：`heartbeat-policy.ts` 控制心跳任务的触发条件
- **重试提示**：`retry-hint.ts` 为失败任务生成重试建议
- **防重复触发**：`service.prevents-duplicate-timers.test.ts` 验证不会重复触发
- **顶部小时错开**：`service.jobs.top-of-hour-stagger.test.ts` 防止所有任务同时触发

### 任务流注册表

`src/tasks/` 提供更通用的任务流管理：
- SQLite 持久化存储（`task-flow-registry.store.sqlite.ts`）
- 任务状态机（pending → running → completed/failed）
- 任务审计日志（`task-registry.audit.ts`）
- 进程状态追踪（`task-registry.process-state.ts`）

---

## 9. TaskFlow 任务流注册表

**对应 AgentOS 层次：编排层 / 跨 session 任务跟踪**

TaskFlow 是 OpenClaw 内置的**跨 session 任务跟踪单元**，定义在 `src/tasks/task-flow-registry.types.ts`。它不是消息，也不是事件队列，而是一个有状态的工作项，贯穿任务从创建到完成的完整生命周期。

与 Cron 的区别：Cron 负责**触发**（什么时候启动 Agent），TaskFlow 负责**跟踪**（一个任务从开始到结束的状态流转）。两者经常配合使用：Cron 触发 Agent，Agent 创建 TaskFlow 跟踪执行进度。

### 核心数据结构

```typescript
// src/tasks/task-flow-registry.types.ts
type TaskFlowRecord = {
  flowId: string;
  syncMode: "task_mirrored" | "managed";
  ownerKey: string;        // 绑定的 agent session key
  controllerId?: string;   // 创建方标识（如 "webhooks/hr-leave-events"）
  revision: number;        // 乐观锁版本号，每次状态变更递增
  status: TaskFlowStatus;
  notifyPolicy: "done_only" | "state_changes" | "silent";
  goal: string;            // 任务意图描述，agent 读取后决定如何处理
  currentStep?: string;    // 当前执行步骤（供外部系统跟踪进度）
  stateJson?: JsonValue;   // 任意业务状态（如请假单详情）
  waitJson?: JsonValue;    // 等待中的上下文（如等待审批的信息）
  blockedTaskId?: string;  // 阻塞本 flow 的子任务 id
  blockedSummary?: string;
  cancelRequestedAt?: number;
  createdAt: number;
  updatedAt: number;
  endedAt?: number;
};
```

### 状态机

```
create_flow
    │
    ▼
 queued ──── agent 开始处理 ──→ running
                                  │
                    ┌─────────────┼──────────────┐
                    ▼             ▼              ▼
                 waiting       blocked     succeeded
                    │             │         failed
              resume_flow /  子任务完成     cancelled
              外部系统恢复    自动恢复         lost
                    │             │
                    └──────→ running
```

| 状态 | 含义 |
|------|------|
| `queued` | 已创建，等待 agent 处理 |
| `running` | agent 正在处理 |
| `waiting` | 主动暂停，等待外部输入（如人工审批） |
| `blocked` | 被子任务阻塞，子任务完成后自动恢复 |
| `succeeded` | 正常完成 |
| `failed` | 执行失败 |
| `cancelled` | 已取消 |
| `lost` | 超时或异常丢失 |

### 两种同步模式

**`managed`（外部驱动）**：由外部系统显式调用 API 控制状态流转（`create_flow` → `set_waiting` → `resume_flow` → `finish_flow`）。适合业务系统通过 webhooks 插件推送事件的场景。

**`task_mirrored`（任务镜像）**：TaskFlow 状态自动跟随其关联子任务的状态。子任务完成 → flow 自动 `succeeded`；子任务失败 → flow 自动 `failed`。适合 agent 自主发起子任务、外部系统只需查询进度的场景。

### 通知策略（notifyPolicy）

控制 TaskFlow 状态变化时是否向 agent 发送通知：

| 值 | 行为 |
|----|------|
| `done_only` | 仅在终态（succeeded / failed / cancelled）时通知 |
| `state_changes` | 每次状态变更都通知 |
| `silent` | 不通知，agent 自行轮询或由子任务驱动 |

### 乐观锁并发控制

每次状态变更操作都需要传入 `expectedRevision`，与当前 `revision` 不匹配则返回 `revision_conflict`，防止并发写冲突。这是 TaskFlow 支持多方（外部系统 + agent + 子任务）同时操作同一工作项的关键机制。

### 子任务挂载（runTask）

TaskFlow 可以挂载多个子任务，子任务由 agent 或 ACP runtime 执行。子任务状态汇总到 `taskSummary`，外部系统可通过 `get_task_summary` 查询整体进度：

```
TaskFlow（父）
  ├── Task 1：财务核查（subagent runtime）
  ├── Task 2：材料审查（subagent runtime）
  └── Task 3：风险汇总（acp runtime）
```

子任务全部完成后，`task_mirrored` 模式的 TaskFlow 自动进入终态。

### 持久化与跨 session 存活

TaskFlow 持久化到 SQLite（`task-flow-registry.store.sqlite.ts`），gateway 重启后自动恢复。保留期为 **7 天**（终态后），过期自动清理（`task-flow-registry.maintenance.ts`）。

这是 TaskFlow 与普通消息的本质区别：**TaskFlow 不依赖 session 存活**，session 重启后 flow 依然在，agent 重新上线后可以继续处理未完成的工作项。

### 与 webhooks 插件的集成

`extensions/webhooks` 插件将 TaskFlow 暴露为 HTTP 接口，业务系统通过 `POST /plugins/webhooks/<routeId>` 推送事件，openclaw 将其转换为 TaskFlow 操作并唤醒对应 agent session。支持的 action：

| action | 说明 |
|--------|------|
| `create_flow` | 创建新 TaskFlow，唤醒 agent |
| `get_flow` | 查询 TaskFlow 状态 |
| `list_flows` | 列出所有 TaskFlow |
| `find_latest_flow` | 查找最新 TaskFlow |
| `set_waiting` | 将 flow 置为等待状态（如等待人工审批） |
| `resume_flow` | 恢复等待中的 flow |
| `finish_flow` | 标记 flow 成功完成 |
| `fail_flow` | 标记 flow 失败 |
| `request_cancel` | 请求取消 flow |
| `cancel_flow` | 强制取消 flow 及其子任务 |
| `run_task` | 在 flow 下创建子任务 |
| `get_task_summary` | 查询子任务汇总状态 |
| `resolve_flow` | 通过 token 解析 flow（用于审批回调） |

### 审计与可观测性

`task-flow-registry.audit.ts` 和 `task-registry.audit.ts` 提供完整的审计日志，记录每次状态变更的时间、操作方和原因，支持事后追溯。

---

## 10. Hook 事件系统

**对应 AgentOS 层次：编排层 / 事件驱动**

Hook 系统让 Agent 能够响应外部事件（邮件、Webhook 等），实现事件驱动的自主行为。

### Hook 类型

`src/hooks/` 支持：

| Hook 类型 | 说明 |
|-----------|------|
| Gmail Watcher | 监听 Gmail 收件箱，新邮件触发 Agent（`gmail-watcher.ts`） |
| Webhook | 接收外部 HTTP 回调（`plugin-sdk/webhook-ingress.ts`） |
| 内部 Hook | `before_agent_reply`、`after_agent_reply` 等生命周期钩子 |
| 插件 Hook | 插件注册的自定义 Hook（`plugin-hooks.ts`） |

### Hook 执行策略

- **fire-and-forget**：异步触发，不阻塞主流程（`fire-and-forget.ts`）
- **策略控制**：`policy.ts` 控制 Hook 的触发条件和权限
- **工作区隔离**：每个工作区有独立的 Hook 配置（`workspace.ts`）

---

## 11. 多渠道接入层

**对应 AgentOS 层次：渠道/接入层**

OpenClaw 的渠道系统是其作为"个人 AI 助手网关"的核心差异化能力——同一个 Agent 可以同时在多个消息平台上响应用户。

### 支持的渠道（extensions/ 目录）

| 类别 | 渠道 |
|------|------|
| 即时通讯 | Telegram、WhatsApp、Signal、Discord、Slack、iMessage、Line、Zalo |
| 企业协作 | Microsoft Teams、Feishu（飞书）、Google Chat、Mattermost、Nextcloud Talk |
| 社交平台 | Twitch、Nostr、Tlon、IRC |
| 国内平台 | QQ Bot、小米、Synology Chat |
| 语音/实时 | Voice Call、Talk Voice、Azure Speech、Deepgram |
| 开发者 | Webhooks、Admin HTTP RPC、QA Channel |

### 渠道架构设计

`src/channels/` 实现了渠道的通用抽象：

- **入站去抖**：`inbound-debounce-policy.ts`，防止群聊消息风暴
- **线程绑定**：`thread-bindings-policy.ts`，将渠道线程与 Agent Session 绑定
- **提及门控**：`mention-gating.ts`，群聊中只响应 @提及
- **状态反应**：`status-reactions.ts`，用 emoji 反应表示 Agent 处理状态
- **草稿流**：`draft-stream-loop.ts`，流式输出时实时更新消息草稿
- **会话路由**：`route-projection.ts`，将渠道消息路由到正确的 Agent Session

### 渠道插件契约

每个渠道插件实现 `ChannelPlugin` 接口（`src/channels/plugins/`），核心方法：
- `startListening()`：启动消息监听
- `sendMessage()`：发送回复
- `getAccountInfo()`：获取账号信息

---

## 12. MCP 协议集成

**对应 AgentOS 层次：工具层 / 协议**

MCP（Model Context Protocol）是 Anthropic 提出的工具调用标准协议。OpenClaw 既是 MCP 客户端（消费外部 MCP 服务器的工具），也是 MCP 服务器（将自身工具暴露给外部）。

### 作为 MCP 客户端

`src/agents/mcp-*.ts` 支持：
- **stdio 传输**：`mcp-stdio-transport.ts`，通过子进程与 MCP 服务器通信
- **HTTP 传输**：`mcp-http.ts`，通过 HTTP 连接远程 MCP 服务器
- **Bundle MCP**：`pi-bundle-mcp-runtime.ts`，将 MCP 工具打包进 Agent 运行时
- **工具物化**：`pi-bundle-mcp-tools.materialize.ts`，将 MCP 工具转换为 Pi 工具格式

### 作为 MCP 服务器

`src/mcp/` 将 OpenClaw 自身的工具暴露为 MCP 服务器：
- `openclaw-tools-serve.ts`：将核心工具暴露为 MCP 端点
- `plugin-tools-serve.ts`：将插件工具暴露为 MCP 端点
- `channel-server.ts`：渠道工具的 MCP 服务器
- `tools-stdio-server.ts`：stdio 模式的 MCP 服务器

### HTTP MCP 网关

`src/gateway/mcp-http.ts` 提供 HTTP 模式的 MCP 网关，支持外部工具通过标准 MCP 协议接入 OpenClaw。

---

## 13. ACP 协议支持

**对应 AgentOS 层次：编排层 / 跨 Agent 通信**

ACP（Agent Communication Protocol）是新兴的 Agent 间通信标准。`src/acp/` 实现了完整的 ACP 服务器和客户端。

### 核心能力

| 组件 | 说明 |
|------|------|
| `acp/server.ts` | ACP 服务器，接受外部 Agent 连接 |
| `acp/client.ts` | ACP 客户端，连接外部 ACP 服务器 |
| `acp/translator.ts` | ACP 消息 ↔ OpenClaw 内部格式转换 |
| `acp/event-ledger.ts` | 事件账本，追踪 Agent 间消息历史 |
| `acp/permission-relay.ts` | 权限中继，子 Agent 的权限审批转发给父 Agent |
| `acp/persistent-bindings.ts` | 持久化 ACP 会话绑定 |
| `acp/session-interaction-mode.ts` | 会话交互模式（同步/异步） |

### ACP 与子 Agent 系统的关系

ACP 是跨进程的 Agent 通信协议，而子 Agent 系统（`subagent-*.ts`）是进程内的 Agent 编排。两者互补：
- 进程内：子 Agent 系统，低延迟，共享内存
- 跨进程/跨机器：ACP 协议，标准化，可互操作

---

## 14. 沙箱执行环境

**对应 AgentOS 层次：安全与治理**

OpenClaw 提供多层次的沙箱隔离，让 Agent 执行代码和命令时不会影响宿主系统。

### 沙箱类型

`src/agents/sandbox/` 支持：

| 沙箱类型 | 说明 |
|----------|------|
| Docker 沙箱 | 在 Docker 容器中执行命令（`sandbox/docker.js`） |
| SSH 沙箱 | 通过 SSH 连接远程沙箱（`sandbox/ssh.js`） |
| 浏览器沙箱 | 隔离的浏览器实例（`sandbox/browser.js`） |
| 本地沙箱 | 受限的本地执行环境 |

### 沙箱工具策略

`sandbox/tool-policy.ts` 控制沙箱内可用的工具集，防止沙箱内的 Agent 执行越权操作。

### 文件系统桥接

`sandbox/fs-bridge.ts` 提供沙箱内外的文件系统桥接，支持：
- 路径映射（宿主路径 ↔ 沙箱路径）
- 可写路径限制
- 重命名目标解析

---

## 15. 安全与审计体系

**对应 AgentOS 层次：安全与治理**

`src/security/` 是 OpenClaw 的安全审计模块，提供全面的安全检查和策略执行。

### 审计维度

| 审计类型 | 说明 |
|----------|------|
| 渠道安全 | `audit-channel.ts`，检查渠道配置的安全性 |
| 网关安全 | `audit-gateway.ts`，检查网关暴露面和认证配置 |
| 插件信任 | `audit-plugins-trust.ts`，验证插件来源和签名 |
| 工具策略 | `audit-tool-policy.ts`，检查工具执行策略 |
| 沙箱配置 | `audit-sandbox-docker-config.ts`，验证 Docker 沙箱配置 |
| Skill 扫描 | `skill-scanner.ts`，扫描 Skill 中的潜在安全问题 |
| 外部内容 | `external-content.ts`，防止外部内容注入攻击 |
| 文件系统 | `audit-fs.ts`，检查文件系统访问权限 |

### 关键安全机制

- **SSRF 防护**：`plugin-sdk/ssrf-policy.ts`，防止服务端请求伪造
- **DM 策略**：`security/dm-policy-shared.ts`，控制私信访问权限
- **上下文可见性**：`context-visibility.ts`，控制哪些信息对 Agent 可见
- **危险配置标记**：`dangerous-config-flags.ts`，标记高风险配置项
- **Windows ACL**：`windows-acl.ts`，Windows 平台的访问控制列表管理

---

## 16. 插件化架构（Plugin SDK）

**对应 AgentOS 层次：所有层次的扩展机制**

Plugin SDK 是 OpenClaw 架构的核心设计原则——核心保持插件无关，所有具体能力通过插件实现。

### 插件边界原则

```
核心（src/）
  ↕ 只通过 plugin-sdk/* 和 manifest 元数据交互
插件（extensions/）
  ↕ 不能访问核心内部实现
```

### Plugin SDK 提供的能力

`src/plugin-sdk/` 包含 400+ 文件，覆盖：

| 能力域 | 关键文件 |
|--------|---------|
| 渠道开发 | `channel-contract.ts`、`channel-lifecycle.ts`、`channel-reply-pipeline.ts` |
| 提供者开发 | `provider-entry.ts`、`provider-stream.ts`、`provider-auth.ts` |
| 工具注册 | `tool-plugin.ts`、`tool-payload.ts` |
| 记忆扩展 | `memory-core.ts`、`memory-core-host-engine-*.ts` |
| 上下文引擎 | 通过 `context-engine/registry.ts` 注册 |
| 媒体生成 | `image-generation-core.ts`、`video-generation-core.ts`、`music-generation-core.ts` |
| 语音/TTS | `speech-core.ts`、`tts-runtime.ts`、`realtime-voice.ts` |
| 审批流程 | `approval-runtime.ts`、`approval-handler-runtime.ts` |
| 浏览器控制 | `browser-bridge.ts`、`browser-cdp.ts` |

### 插件生命周期

```
插件发现（manifest 扫描）
  → 激活规划（resolveActivationPlan）
  → 插件加载（facade-loader.ts）
  → 渠道/提供者注册
  → 运行时可用
```

### 外部官方插件 vs 捆绑插件

- **捆绑插件**：随核心发布，通过 facade-runtime 加载
- **外部官方插件**：独立包，通过 registry-aware facade-runtime 加载，不进入核心 dist

---

## 17. OpenAI 兼容 HTTP 网关

**对应 AgentOS 层次：接入层 / 互操作性**

OpenClaw 暴露标准 OpenAI 兼容 HTTP 接口，让任何支持 OpenAI API 的工具都能直接接入。

### 支持的端点

| 端点 | 文件 | 说明 |
|------|------|------|
| `POST /v1/chat/completions` | `gateway/openai-http.ts` | 标准 Chat Completions API |
| `POST /v1/responses` | `gateway/openresponses-http.ts` | OpenAI Responses API |
| `GET /v1/models` | `gateway/models-http.ts` | 模型列表 |
| `POST /v1/embeddings` | `gateway/embeddings-http.ts` | 嵌入向量 |

### 关键特性

- **流式响应**：支持 `stream: true`，SSE 格式推送
- **推理参数**：`openai-reasoning-effort.ts`，透传 reasoning_effort 参数
- **工具调用**：完整支持 OpenAI function calling 格式
- **图片预算**：`openai-http.image-budget.ts`，控制图片 Token 消耗
- **模型别名**：`model-runtime-aliases.ts`，支持模型名称映射

这意味着 OpenClaw 可以作为本地 LLM 代理，让 Cursor、Continue、Cline 等 AI 编程工具通过标准 OpenAI API 接入任意模型。

---

## 18. 轨迹追踪与可观测性

**对应 AgentOS 层次：安全与治理 / 可观测性**

### 轨迹系统（Trajectory）

`src/trajectory/` 记录 Agent 执行的完整轨迹：

- **元数据**：`metadata.ts`，记录每次 Run 的基本信息
- **导出**：`export.ts`，将轨迹导出为结构化格式
- **清理**：`cleanup.ts`，定期清理过期轨迹

### 诊断与可观测性

| 组件 | 说明 |
|------|------|
| `extensions/diagnostics-otel/` | OpenTelemetry 集成，支持分布式追踪 |
| `extensions/diagnostics-prometheus/` | Prometheus 指标暴露 |
| `src/agents/cache-trace.ts` | Prompt Cache 命中率追踪 |
| `src/agents/anthropic-payload-log.ts` | Anthropic API 请求日志 |
| `src/gateway/ws-log.ts` | WebSocket 消息日志 |

### 健康检查

`src/flows/` 提供 `openclaw doctor` 命令的健康检查框架：
- 渠道健康检查（`channel-setup.status.ts`）
- 核心检查（`doctor-core-checks.ts`）
- 自动修复（`doctor-repair-flow.ts`）

---

## 19. 能力全景图

将 OpenClaw 的能力映射到 AgentOS 的标准层次：

```
┌─────────────────────────────────────────────────────────────────────┐
│                        接入层（Clients）                              │
│  Web UI · CLI/TUI · macOS/iOS/Android · 20+ 消息渠道                 │
├─────────────────────────────────────────────────────────────────────┤
│                     协议适配层（Protocols）                           │
│  WebSocket RPC · OpenAI HTTP · MCP Server · ACP Server              │
├─────────────────────────────────────────────────────────────────────┤
│                      编排层（Orchestration）                          │
│  子 Agent 系统 · Cron 调度 · TaskFlow 任务流 · Hook 事件 · 任务流注册表 │
├─────────────────────────────────────────────────────────────────────┤
│                    Agent 运行时（Pi Runner）                          │
│  主循环 · Attempt 循环 · 模型降级 · Auth 轮换 · 流式输出              │
├──────────────────┬──────────────────┬───────────────────────────────┤
│   上下文引擎      │    记忆系统        │       Skill 系统              │
│  可插拔引擎       │  MEMORY.md        │  6 类来源加载                  │
│  Token 估算       │  daily-notes      │  字符限制降级                  │
│  自动 Compaction  │  dream-report     │  工作区同步                    │
│                  │  向量检索          │                               │
├──────────────────┴──────────────────┴───────────────────────────────┤
│                       工具执行层（Tools）                             │
│  Files · Runtime · Web · Memory · Sessions · Agents · Messaging      │
│  工具策略管道 · 循环检测 · 执行审批 · 结果截断                         │
├─────────────────────────────────────────────────────────────────────┤
│                    模型提供者层（Providers）                           │
│  50+ 提供者 · Harness 路由 · 模型降级 · API Key 轮换                  │
├─────────────────────────────────────────────────────────────────────┤
│                    安全与治理（Security）                             │
│  沙箱隔离 · SSRF 防护 · 工具策略 · 审计体系 · 插件信任                │
├─────────────────────────────────────────────────────────────────────┤
│                    插件化架构（Plugin SDK）                           │
│  渠道插件 · 提供者插件 · 工具插件 · 记忆插件 · 媒体插件               │
└─────────────────────────────────────────────────────────────────────┘
```

### 与主流 AgentOS 框架的对比

| 能力 | OpenClaw | LangGraph | AutoGen | AIOS |
|------|----------|-----------|---------|------|
| 嵌入式运行时 | ✅ Pi Runner | ❌ | ❌ | ✅ |
| 多渠道接入 | ✅ 20+ 渠道 | ❌ | ❌ | ❌ |
| 持久化记忆 | ✅ 多层次 | 部分 | 部分 | ✅ |
| 自动上下文压缩 | ✅ | ❌ | ❌ | ❌ |
| 子 Agent 编排 | ✅ 树状 | ✅ 图状 | ✅ | ❌ |
| Cron 自主调度 | ✅ | ❌ | ❌ | ❌ |
| TaskFlow 任务跟踪 | ✅ 持久化状态机 | 部分 | ❌ | ❌ |
| MCP 协议 | ✅ 双向 | 部分 | ❌ | ❌ |
| ACP 协议 | ✅ | ❌ | ❌ | ❌ |
| 沙箱执行 | ✅ Docker/SSH | ❌ | ❌ | ❌ |
| OpenAI 兼容网关 | ✅ | ❌ | ❌ | ❌ |
| 插件化架构 | ✅ 完整 SDK | 部分 | 部分 | ❌ |
| 本地优先 | ✅ | ❌ | ❌ | ❌ |

### 核心差异化

OpenClaw 作为 AgentOS 的核心差异化在于：

1. **本地优先（Local-first）**：运行在用户设备上，数据不离开本地，隐私有保障
2. **多渠道统一**：同一个 Agent 同时在 Telegram、WhatsApp、Slack 等 20+ 渠道响应
3. **完整的 Pi 运行时**：不依赖外部框架，自研嵌入式 Agent 内核，控制力强
4. **自主性**：Cron + Hook 让 Agent 能主动行动，不只是被动响应
5. **互操作性**：OpenAI 兼容 HTTP + MCP + ACP，与整个 AI 生态无缝集成

---

## 参考资料

- 架构设计文档：`adoc/架构设计文档.md`
- 核心源码：`src/agents/`、`src/context-engine/`、`src/plugin-sdk/`
- 渠道插件：`extensions/<channel>/`
- 提供者插件：`extensions/<provider>/`
- [AIOS: LLM Agent Operating System](https://arxiv.org/abs/2403.16971)（Rutgers, COLM 2025）
- [What Is an Agentic Operating System](https://www.mindstudio.ai/blog/what-is-agentic-operating-system)（MindStudio, 2025）
- [Agent Operating Systems Blueprint Architecture](https://www.preprints.org/manuscript/202509.0077/v1)（Preprints, 2025）
