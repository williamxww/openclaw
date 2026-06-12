# OpenClaw Channel 系统源码分析

> 以 QQ Bot channel 为具体案例，梳理 channel 系统的完整架构与数据流。

---

## 一、整体架构

```
外部消息（QQ WebSocket）
        │
        ▼
extensions/qqbot/src/engine/gateway/gateway.ts
  handleMessage()                                 ← 消息入口
        │
        ▼
extensions/qqbot/src/engine/gateway/outbound-dispatch.ts
  dispatchOutbound()                              ← 调用 openclaw channel turn
        │  runtime.channel.turn.run(...)
        ▼
src/channels/turn/kernel.ts
  runChannelTurn()                                ← openclaw channel turn 核心
        │
        ├── ingest()        ← 标准化消息
        ├── classify()      ← 事件分类
        ├── preflight()     ← 门控检查
        ├── resolveTurn()   ← 组装 AssembledChannelTurn
        └── dispatchAssembledChannelTurn()
              │
              ▼
        auto-reply 管线（runAgentTurnWithFallback）
              │
              ▼
        Pi 嵌入式运行时（模型调用 / 工具执行）
              │
              ▼
        delivery.deliver()  ← 回写 QQ Bot
```

---

## 二、核心类型

### `src/channels/turn/types.ts`

#### `ChannelTurnAdapter<TRaw>`（第 293 行）

channel 插件实现的核心接口，`runChannelTurn` 依赖它完成入站事件处理：

```typescript
// types.ts:293
export type ChannelTurnAdapter<TRaw, TDispatchResult = DispatchFromConfigResult> = {
  ingest: (raw: TRaw) => Promise<NormalizedTurnInput | null> | NormalizedTurnInput | null;
  classify?: (input: NormalizedTurnInput) => Promise<ChannelEventClass> | ChannelEventClass;
  preflight?: (
    input: NormalizedTurnInput,
    eventClass: ChannelEventClass,
  ) => Promise<PreflightFacts | ChannelTurnAdmission | null | undefined> | ...;
  resolveTurn: (
    input: NormalizedTurnInput,
    eventClass: ChannelEventClass,
    preflight: PreflightFacts,
  ) => Promise<ChannelTurnResolved<TDispatchResult>> | ChannelTurnResolved<TDispatchResult>;
  onFinalize?: (result: ChannelTurnResult<TDispatchResult>) => Promise<void> | void;
};
```

四个方法的职责：

| 方法 | 必填 | 职责 |
|------|------|------|
| `ingest` | ✅ | 原始消息 → `NormalizedTurnInput`；返回 null 则 drop |
| `classify` | ⬜ | 判断事件类型（message/reaction/lifecycle），决定是否能开启 agent turn |
| `preflight` | ⬜ | 门控检查（allowFrom 权限、群聊去抖、mention 检测），返回 admission drop/dispatch |
| `resolveTurn` | ✅ | 组装完整的 `AssembledChannelTurn`，含 ctxPayload、deliver 函数、session 路由 |

#### `ChannelTurnAdmission`（第 29 行）

turn 的最终处置决策，贯穿整个 pipeline：

```typescript
// types.ts:29
export type ChannelTurnAdmission =
  | { kind: "dispatch"; reason?: string }    // 正常投递
  | { kind: "observeOnly"; reason: string }  // 仅观察，用 noop deliver
  | { kind: "handled"; reason: string }      // 已处理（如 reaction），不起 agent turn
  | { kind: "drop"; reason: string; recordHistory?: boolean }; // 丢弃
```

#### `NormalizedTurnInput`（第 36 行）

```typescript
// types.ts:36
export type NormalizedTurnInput = {
  id: string;           // 消息唯一 id（用于日志和去重）
  timestamp?: number;
  rawText: string;      // 原始文本，用于历史记录
  textForAgent?: string; // 给模型看的文本（可经过 mention 清洗）
  textForCommands?: string; // 命令解析用文本
  raw?: unknown;         // 原始事件对象，供后续步骤深入访问
};
```

#### `AssembledChannelTurn`（第 342 行）

`resolveTurn` 的返回值，包含驱动一次完整 agent turn 所需的全部信息：

```typescript
// types.ts:342
export type AssembledChannelTurn = {
  cfg: OpenClawConfig;
  channel: string;
  accountId?: string;
  agentId: string;
  routeSessionKey: string;     // 路由到哪个 session
  storePath: string;           // session store 路径
  ctxPayload: FinalizedMsgContext; // 消息上下文（传入 Pi 运行时）
  recordInboundSession: RecordInboundSession;
  dispatchReplyWithBufferedBlockDispatcher: DispatchReplyWithBufferedBlockDispatcher;
  delivery: ChannelEventDeliveryAdapter; // 回复投递适配器（含 deliver 函数）
  // ... 可选的 record / history / botLoopProtection 等
};
```

#### `ChannelEventDeliveryAdapter`（第 273 行）

模型输出 → 实际发送到 QQ 的抽象：

```typescript
// types.ts:273
export type ChannelEventDeliveryAdapter = {
  preparePayload?: (payload, info) => Promise<ReplyPayload> | ReplyPayload;
  deliver: (payload, info) => Promise<ChannelDeliveryResult | void>;
  durable?: false | ChannelTurnDurableDeliveryOptions | ((payload, info) => ...);
  onDelivered?: (payload, info, result) => Promise<void> | void;
  onError?: (err, info) => void;
};
```

---

## 三、Channel Turn Kernel

### `src/channels/turn/kernel.ts`

#### `runChannelTurn()`（第 572 行）

turn 的主入口，执行 5 个阶段：

```typescript
// kernel.ts:572
export async function runChannelTurn<TRaw, TDispatchResult>(
  params: RunChannelTurnParams<TRaw, TDispatchResult>,
): Promise<ChannelTurnResult<TDispatchResult>> {
```

**阶段流程**：

```
① ingest     (kernel.ts:577)   adapter.ingest(raw) → NormalizedTurnInput | null
              null → drop admission，返回，不继续

② classify   (kernel.ts:594)   adapter.classify(input) → ChannelEventClass
              canStartAgentTurn=false → handled admission，返回

③ preflight  (kernel.ts:604)   adapter.preflight(input, eventClass) → PreflightFacts
              drop/handled admission → 记录历史，返回

④ resolveTurn (kernel.ts:623)  adapter.resolveTurn(input, eventClass, preflight)
              → ChannelTurnResolved（含 ctxPayload 和 runDispatch）

⑤ dispatch   (kernel.ts:638)   dispatchResolvedChannelTurn(resolved)
              → 触发 agent turn → delivery.deliver() 回复
```

**关键代码段（kernel.ts:577-668）**：

```typescript
// kernel.ts:577
const input = await params.adapter.ingest(params.raw);
if (!input) {
  // drop
  return { admission: { kind: "drop", reason: "ingest-null" }, dispatched: false };
}

// kernel.ts:594
const eventClass = (await params.adapter.classify?.(input)) ?? DEFAULT_EVENT_CLASS;
if (!eventClass.canStartAgentTurn) {
  return { admission: { kind: "handled", reason: `event:${eventClass.kind}` }, ... };
}

// kernel.ts:604
const preflight = normalizePreflight(await params.adapter.preflight?.(input, eventClass));
const preflightAdmission = preflight.admission;
if (preflightAdmission && preflightAdmission.kind !== "dispatch" && ...) {
  // drop 或 handled
  return { admission: preflightAdmission, dispatched: false };
}

// kernel.ts:623
const resolved = await params.adapter.resolveTurn(input, eventClass, preflight);
```

#### `dispatchAssembledChannelTurn()`（第 285 行）

```typescript
// kernel.ts:285
export async function dispatchAssembledChannelTurn(
  params: AssembledChannelTurn,
): Promise<ChannelTurnResult> {
```

这里把 `AssembledChannelTurn.delivery.deliver` 和 `dispatchReplyWithBufferedBlockDispatcher` 拼接起来：
- `dispatchReplyWithBufferedBlockDispatcher` 负责驱动 Pi 运行时（模型调用、工具循环）
- 每次模型输出一个 block，都调用 `delivery.deliver(payload, info)` 发送给用户
- 支持 `durable` 模式（outbound queue 持久投递）

---

## 四、ChannelPlugin 接口

### `src/channels/plugins/types.plugin.ts`（第 47 行）

channel 插件需要实现的完整合约：

```typescript
// types.plugin.ts:47
export type ChannelPlugin<ResolvedAccount = any, Probe, Audit> = {
  id: ChannelId;
  meta: ChannelMeta;
  capabilities: ChannelCapabilities; // chatTypes / media / reactions / threads / blockStreaming
  reload?: { configPrefixes: string[] }; // 哪些 config 路径变化触发 channel 重启
  config: ChannelConfigAdapter<ResolvedAccount>; // 读取和解析账号配置
  configSchema?: ChannelConfigSchema;
  setup?: ChannelSetupAdapter;       // setup wizard 表单
  outbound?: ChannelOutboundAdapter; // 发送文本/媒体/分块
  status?: ChannelStatusAdapter;     // 运行态快照
  gateway?: ChannelGatewayAdapter<ResolvedAccount>; // startAccount / logoutAccount
  message?: ChannelMessageAdapterShape; // 新式消息适配器（defineChannelMessageAdapter）
  messaging?: ChannelMessagingAdapter; // target 格式化、normalizeTarget
  approvalCapability?: ChannelApprovalCapability;
  // ...其他可选 adapter
};
```

**最关键的两个字段**：

- `gateway.startAccount`：启动 channel（WebSocket 连接、轮询、webhook 注册等）
- `message` / `outbound`：实际发送消息到外部平台

---

## 五、Channel 注册机制

### `extensions/qqbot/index.ts`（第 1 行）

channel 入口通过 `defineBundledChannelEntry` 声明：

```typescript
// qqbot/index.ts:1
import { defineBundledChannelEntry, ... } from "openclaw/plugin-sdk/channel-entry-contract";

export default defineBundledChannelEntry({
  id: "qqbot",
  name: "QQ Bot",
  importMetaUrl: import.meta.url,
  plugin: { specifier: "./channel-plugin-api.js", exportName: "qqbotPlugin" },
  secrets: { specifier: "./secret-contract-api.js", exportName: "channelSecrets" },
  runtime: { specifier: "./runtime-api.js", exportName: "setQQBotRuntime" },
  registerFull: registerQQBotFull,
});
```

### `src/plugin-sdk/channel-entry-contract.ts` — `defineBundledChannelEntry()`（第 308 行）

```typescript
// channel-entry-contract.ts:308
export function defineBundledChannelEntry<TPlugin>({
  id, name, importMetaUrl, plugin, ...
}): BundledChannelEntryContract<TPlugin> {
  return {
    kind: "bundled-channel-entry",
    register(api: OpenClawPluginApi) {
      // 注册模式: cli-metadata / tool-discovery / discovery / full
      const channelPlugin = loadChannelPlugin();
      api.registerChannel({ plugin: channelPlugin }); // 注册到全局 channel registry
      setChannelRuntime?.(api.runtime);               // 注入 openclaw runtime 引用
      registerFull?.(api);                            // 注册工具等额外能力
    },
    loadChannelPlugin,    // 懒加载 qqbotPlugin 对象
    loadChannelSecrets,   // 懒加载 secret 描述符
    setChannelRuntime,    // 向 qqbot 注入 openclaw runtime
  };
}
```

`api.registerChannel` 的调用将 `qqbotPlugin` 写入 openclaw 的 channel registry，之后 gateway 启动时调用 `plugin.gateway.startAccount(ctx)` 开始监听消息。

---

## 六、QQ Bot Channel 实现解析

### 6.1 ChannelPlugin 对象

`extensions/qqbot/src/channel.ts` 导出 `qqbotPlugin: ChannelPlugin<ResolvedQQBotAccount>`，核心字段（channel.ts:160 起）：

```typescript
// channel.ts:160
export const qqbotPlugin: ChannelPlugin<ResolvedQQBotAccount> = {
  id: "qqbot",
  capabilities: {
    chatTypes: ["direct", "group"],
    media: true,
    reactions: false,
    threads: false,
    blockStreaming: true,           // 支持流式输出
  },
  reload: { configPrefixes: ["channels.qqbot"] }, // 配置变化时重启本 channel
  // ...
  gateway: {
    startAccount: async (ctx) => {  // channel.ts:232 — 启动 WebSocket 连接
      const { startGateway } = await loadGatewayModule();
      await startGateway({ account, abortSignal, cfg, ... });
    },
    logoutAccount: async ({ accountId, cfg }) => { ... },
  },
};
```

### 6.2 消息接收链路

```
QQ WebSocket 推送事件
  │
  ▼
extensions/qqbot/src/engine/gateway/gateway.ts
  handleMessage(event: QueuedMessage)             // gateway.ts:87
  │  buildInboundContext(event, ...)              // 解析消息、权限检查、媒体下载
  │  若 blocked/skipped → 停止
  │
  ▼
extensions/qqbot/src/engine/gateway/outbound-dispatch.ts
  dispatchOutbound(inbound, { runtime, cfg, account })  // outbound-dispatch.ts:67
  │
  │  // 组装 ctxPayload（FinalizedMsgContext）  outbound-dispatch.ts:336
  │  buildCtxPayload(inbound, runtime, cfg)
  │
  │  // 调用 openclaw runtime 的 turn.run()    outbound-dispatch.ts:163
  ▼
runtime.channel.turn.run({
  channel: "qqbot",
  raw: inbound,
  adapter: {
    ingest: () => ({                              // outbound-dispatch.ts:170
      id: ctxPayload.MessageSid,
      rawText: ctxPayload.RawBody,
      textForAgent: ctxPayload.BodyForAgent,
      ...
    }),
    resolveTurn: () => ({                         // outbound-dispatch.ts:178
      channel: "qqbot",
      routeSessionKey: inbound.route.sessionKey,
      ctxPayload,
      recordInboundSession: runtime.channel.session.recordInboundSession,
      runDispatch: () => runtime.channel.reply.dispatchReplyWithBufferedBlockDispatcher(...)
    }),
  },
})
```

注意：QQ Bot 没有实现 `classify` 和 `preflight`，直接在 `ingest` + `resolveTurn` 里完成所有处理。访问控制（allowFrom 检查）在 `buildInboundContext` 里由 QQ Bot 自己处理，`blocked=true` 时在调用 `runChannelTurn` 之前就已经 return 了。

### 6.3 消息发送链路

模型每输出一个 block，调用 `dispatcherOptions.deliver(payload, info)`（outbound-dispatch.ts:197）：

```
deliver(payload, info)
  │
  ├── info.kind === "tool"   → 收集 toolTexts/toolMediaUrls，工具超时后发送
  │
  └── info.kind === "block"  → 正式回复
        │
        ├── 流式模式 (streamingController)  → streamingController.onDeliver(payload)
        │
        └── 非流式
              ├── parseAndSendMediaTags()    ← 解析 [img:...] 等媒体标签
              ├── handleStructuredPayload()  ← 处理 QQBOT_PAYLOAD: 前缀的结构化输出
              ├── sendTextAsVoiceReply()     ← 语音回复
              └── sendPlainReply()           ← 普通文本 + 图片
```

---

## 七、Gateway 层如何管理 Channel

### `src/gateway/config-reload-plan.ts`（第 94 行）

`channels.*` 配置变化时触发对应 channel 的 restart 动作：

```typescript
// config-reload-plan.ts（channel restart 规则由 channel 插件的 reload.configPrefixes 驱动）
{
  prefix: "agents.list",
  kind: "hot",
  actions: ["restart-heartbeat"],
},
```

QQBot 自己声明的重载触发条件（channel.ts:172）：
```typescript
reload: { configPrefixes: ["channels.qqbot"] }
```

也就是说，修改 `openclaw.json` 里 `channels.qqbot.*` 的任意字段，gateway 热重载时会停止并重启 QQ Bot channel（断开 WebSocket，重新建连），不需要重启进程。

### Channel 启动时序

```
startGatewayServer()
  → registerPlugins()               ← 加载所有 channel 插件，调用各自的 register(api)
  → api.registerChannel(qqbotPlugin) ← qqbotPlugin 写入 channel registry
  → startGatewayChannels()          ← 遍历 registry，调用 plugin.gateway.startAccount()
  → qqbot.gateway.startAccount(ctx) ← 启动 WebSocket 连接，开始接收消息
```

---

## 八、关键文件速查表

| 文件 | 核心内容 |
|------|---------|
| `src/channels/turn/types.ts` | `ChannelTurnAdapter`（293）、`AssembledChannelTurn`（342）、`ChannelTurnAdmission`（29）、`NormalizedTurnInput`（36）、`ChannelEventDeliveryAdapter`（273） |
| `src/channels/turn/kernel.ts` | `runChannelTurn()`（572）、`dispatchAssembledChannelTurn()`（285）、`runPreparedChannelTurnCore()`（404） |
| `src/channels/plugins/types.plugin.ts` | `ChannelPlugin<ResolvedAccount>` 完整接口（47） |
| `src/plugin-sdk/channel-entry-contract.ts` | `defineBundledChannelEntry()`（308）、`loadBundledEntryExportSync()`（262）、注册流程 |
| `extensions/qqbot/index.ts` | QQ Bot channel 入口，`defineBundledChannelEntry` 调用（1） |
| `extensions/qqbot/src/channel.ts` | `qqbotPlugin` 对象（160），`startAccount`（232），消息发送（sendQQBotText/sendQQBotMedia） |
| `extensions/qqbot/src/engine/gateway/gateway.ts` | `startGateway()`（106），`handleMessage()`（87），WebSocket 连接管理 |
| `extensions/qqbot/src/engine/gateway/outbound-dispatch.ts` | `dispatchOutbound()`（67），`buildCtxPayload()`（336），调用 `runtime.channel.turn.run()` |
| `src/gateway/config-reload-plan.ts` | Channel 热重载规则，`agents.list` → restart-heartbeat，`cron` → restart-cron |

---

## 九、实现新 Channel 的最简路径

1. **创建 `extensions/<id>/index.ts`**，调用 `defineBundledChannelEntry`
2. **实现 `ChannelPlugin` 对象**，至少填写：
   - `id`、`meta`、`capabilities`、`config`（账号配置读取）
   - `gateway.startAccount`：在这里建立外部连接，收到消息后调 `runtime.channel.turn.run(adapter)`
3. **实现 `ChannelTurnAdapter`**：
   - `ingest(raw)`：把你的原始消息对象转成 `NormalizedTurnInput`
   - `resolveTurn(input, eventClass, preflight)`：构造 `AssembledChannelTurn`，其中 `delivery.deliver` 实现把 `ReplyPayload.text` 发回给用户
4. **注册到 `openclaw.plugin.json`**：`onStartup: true`

`classify` 和 `preflight` 都是可选的。如果访问控制在 `startAccount` 里自己处理（像 QQ Bot 那样在 `buildInboundContext` 里做 blocked 判断），可以完全不实现这两个方法。
