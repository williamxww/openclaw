# `runEmbeddedPiAgent` 详解

**文件：** `src/agents/pi-embedded-runner/run.ts:406`  
**签名：** `async function runEmbeddedPiAgent(params: RunEmbeddedPiAgentParams): Promise<EmbeddedPiRunResult>`

这是 OpenClaw Agent 执行的核心函数，承担从 "收到一条用户消息" 到 "拿到最终 reply payload" 的全部工作，包含队列调度、模型解析、Auth 管理、多级重试/降级、context compaction 和结果构建。

---

## 一、入队前准备（406–472）

| 行号 | 操作 |
|------|------|
| 411 | `backfillSessionKey` — 补全 sessionKey，确保后续所有组件（hook、LCM、compaction）都收到非空 key |
| 420–421 | `resolveSessionLane` / `resolveGlobalLane` — 计算 session 级和全局级并发 lane |
| 422–423 | `resolveEmbeddedRunSessionQueuePriority` / `resolveEmbeddedRunLaneTimeoutMs` — 确定入队优先级和 lane 超时 |
| 447–453 | 根据 `messageChannel` 决定 `toolResultFormat`（markdown vs plain） |
| 456–472 | 定义 `throwIfAborted`，入队前先检查一次 abortSignal |

---

## 二、双层入队（474–476）

```
enqueueSession(                // session 级队列：同一 session 串行
  () => enqueueGlobal(         // 全局队列：跨 session 并发限流
    async () => { ... }
  )
)
```

**作用：** 防止同一 session 并发执行，同时对全局调用量限流。所有后续步骤都在 `enqueueGlobal` 的回调体内执行。

---

## 三、Startup 阶段（478–1196）

每个子阶段完成后调用 `startupStages.mark(...)` 记录耗时，首次 Attempt dispatch 时统一 emit 慢启动日志。

### 3.1 初始化追踪器（479）

```ts
const startupStages = createEmbeddedRunStageTracker();
```

### 3.2 解析工作区 `workspace`（515–520）

```ts
const workspaceResolution = resolveRunWorkspaceDir({
  workspaceDir: params.workspaceDir,
  sessionKey, agentId, config,
});
```

处理 `null`/空字符串/非 string fallback、`~` 展开、控制字符剥离（OC-19 安全加固），同时解析出 `agentId`。

### 3.3 加载 runtime plugins `runtime-plugins`（531–136）

```ts
ensureRuntimePluginsLoaded({ config, workspaceDir, allowGatewaySubagentBinding });
```

确保当前 provider 所需的 runtime 插件已加载进进程。

### 3.4 cron `before_agent_reply` hook（164–186）

仅 `trigger === "cron"` 时执行。若 hook 返回 `handled: true`，**整个 run 短路**，直接返回 hook 提供的 reply payload，不走模型。

### 3.5 Hook 模型选择（188–197）

```ts
const hookSelection = await resolveHookModelSelection({ prompt, provider, modelId, hookRunner, hookContext });
provider = hookSelection.provider;
modelId = hookSelection.modelId;
```

hook 可以在运行前改写 provider/model。

### 3.6 选择 AgentHarness（200–218）

```ts
await ensureSelectedAgentHarnessPlugin({ provider, modelId, config, ... });
const agentHarness = selectAgentHarness({ ... });
const pluginHarnessOwnsTransport = agentHarness.id !== "pi";
```

`agentHarness.id` 决定后续用 Pi 内置 transport（OpenAI SDK）还是由插件（如 Codex harness）拥有 transport。

### 3.7 解析 model manifest `model-resolution`（229–293）

```ts
const modelResolution = await resolveModelAsync(provider, modelId, agentDir, config, ...);
const { model, authStorage, modelRegistry } = modelResolution;
const ctxInfo = resolvedRuntimeModel.ctxInfo;   // context window 大小
```

从 models.json / plugin 动态 hook 解析出 model 对象、context window token 数、API 类型。model 找不到则立即 `throw FailoverError`。

### 3.8 构建 Auth Profile Store（296–580）

关键变量：

| 行号 | 变量 | 含义 |
|------|------|------|
| 300–316 | `authStore` / `attemptAuthProfileStore` | 主 auth store / attempt 级 scoped store |
| 870–884 | `profileCandidates` | 本次 run 可用的 auth profile id 列表（按优先级排序） |
| 885 | `profileIndex` | 当前使用的 profile 指针 |

### 3.9 初始化 Auth Profile（895–984）

```ts
const { advanceAuthProfile, initializeAuthProfile, maybeRefreshRuntimeAuthForAuthError, stopRuntimeAuthRefreshTimer }
  = createEmbeddedRunAuthController({ ... });
await initializeAuthProfile();   // 978
```

`initializeAuthProfile` 完成首次 API key / OAuth token 获取，将结果写入 `apiKeyInfo`/`runtimeAuthState`。

### 3.10 解析 Context Engine `context-engine`（1189–1196）

```ts
const contextEngine = await resolveContextEngine(params.config, { agentDir, workspaceDir });
```

Context Engine 负责 compaction（压缩历史对话）。**只初始化一次，跨所有重试复用**，避免每次 attempt 重建连接。

---

## 四、循环计数器 & 状态初始化（1000–1190）

在主循环之前，初始化所有重试限制和运行时状态：

| 行号 | 变量 | 含义 |
|------|------|------|
| 1000–1011 | `executionContract` | `"strict-agentic"` 或 `"default"`，影响 planning-only 重试上限 |
| 1013 | `maxPlanningOnlyRetryAttempts` | planning-only 最大重试次数（由 executionContract 决定） |
| 1017 | `MAX_TIMEOUT_COMPACTION_ATTEMPTS = 2` | 超时触发 compaction 的最大次数 |
| 1018 | `MAX_OVERFLOW_COMPACTION_ATTEMPTS = 3` | 上下文溢出触发 compaction 的最大次数 |
| 1019 | `MAX_RUN_LOOP_ITERATIONS` | 整个 while 循环的硬上限（由 profileCandidates 数量和 config 决定） |
| 1024 | `overflowCompactionAttempts` | 已触发 overflow compaction 次数 |
| 1031 | `autoCompactionCount` | 累计 auto compaction 次数（含 attempt 内部自动触发的） |
| 1034 | `runLoopIterations` | 当前循环迭代次数 |
| 1069–1078 | 各种 retry 计数器 | planning-only / reasoning-only / empty response / compaction continuation 等 |
| 1087–1090 | `idleTimeoutBreakerState` | idle timeout 熔断器状态（防止无输出循环烧钱） |

---

## 五、主循环 `while (true)`（1281–3349）

每次进入循环体代表一次 **Attempt**。

### 5.1 迭代上限检查（1282–1315）

```ts
if (runLoopIterations >= MAX_RUN_LOOP_ITERATIONS) {
  return handleRetryLimitExhaustion(...);   // 1296
}
runLoopIterations += 1;   // 1317
```

### 5.2 组装 Prompt（1326–1342）

```ts
const basePrompt = nextAttemptPromptOverride ?? params.prompt;   // 1326
const promptAdditions = [
  ackExecutionFastPathInstruction,
  planningOnlyRetryInstruction,       // 若上次是 planning-only turn
  reasoningOnlyRetryInstruction,      // 若上次是 reasoning-only turn
  emptyResponseRetryInstruction,      // 若上次空回复
  compactionContinuationRetryInstruction,  // 若 compaction 打断了回复
].filter(Boolean);
const prompt = promptAdditions.length ? `${basePrompt}\n\n${promptAdditions.join("\n\n")}` : basePrompt;
```

### 5.3 构建 RuntimePlan（1350–1378）

```ts
const runtimePlan = buildAgentRuntimePlan({
  provider, modelId, model: effectiveModel,
  harnessId: agentHarness.id,
  sessionAuthProfileId: lastProfileId,
  thinkingLevel: thinkLevel,
  ...
});
```

把 provider/model/harness/auth profile/thinking level 打包成不可变执行计划，传给 backend。

### 5.4 调用模型：`runEmbeddedAttemptWithBackend`（1398）

```ts
const rawAttempt = await runEmbeddedAttemptWithBackend({
  sessionId: activeSessionId,
  sessionFile: activeSessionFile,
  contextEngine,
  contextTokenBudget: ctxInfo.tokens,
  prompt,
  runtimePlan,
  model: applyAuthHeaderOverride(effectiveModel, apiKeyInfo, config),
  ...所有 callback (onPartialReply, onAgentEvent, onToolResult...)
});
```

**这是真正发出模型请求的地方**。内部完成：
- 组装 JSONL session 消息（从 `sessionFile` 读取历史）
- 流式调用 LLM API
- 执行 Tool Call（bash、搜索、messaging 等）
- SDK 内部 auto-compaction（若 harness 支持）

返回 `rawAttempt`，包含 `assistantTexts`、`toolMetas`、`lastAssistant`、`promptError`、`aborted`、`timedOut`、`compactionCount` 等。

### 5.5 结果规范化（1540）

```ts
const attempt = normalizeEmbeddedRunAttemptResult(rawAttempt);
```

提取关键字段：`aborted`、`timedOut`、`promptError`、`promptErrorSource`、`preflightRecovery`、`sessionIdUsed`、`currentAttemptAssistant`…

### 5.6 Idle Timeout 熔断器（1589–1633）

```ts
const breakerStep = stepIdleTimeoutBreaker(idleTimeoutBreakerState, {
  idleTimedOut, completedModelProgress, outputTokens,
});
if (breakerStep.tripped) {
  return handleRetryLimitExhaustion(...);   // 1614
}
```

连续多次 idle timeout 且无任何输出 → 触发熔断，直接终止，防止无输出的 token 烧钱循环（issue #76293）。

---

### 5.7 恢复路径判断树（1635–2469）

按优先级从高到低依次判断：

#### ① preflightRecovery（1683–1693）

```ts
if (preflightRecovery?.handled) {
  if (preflightRecovery.source === "mid-turn") continueFromCurrentTranscript();
  continue;   // 直接重试，不走后续判断
}
```

backend 在 attempt 前已检测到 context overflow 并处理（precheck 阶段），直接重试。

#### ② Live Model Switch（1695–1715）

```ts
const requestedSelection = shouldSwitchToLiveModel({ ... });
if (requestedSelection && canRestartForLiveSwitch) {
  throw new LiveSessionModelSwitchError(requestedSelection);   // 1715
}
```

用户在 session 中请求切换模型（`/model` 命令），当前 attempt 尚未产生任何可见输出 → 抛出 `LiveSessionModelSwitchError`，由外层 `agent-runner-execution.ts` 捕获并用新 model 重启整个 run。

#### ③ Timeout Compaction（1720–1843）

```ts
if (timedOut && !timedOutDuringCompaction && tokenUsedRatio > 0.65) {
  // prompt token 占 context 的 65% 以上时，超时很可能是上下文太长导致的
  timeoutCompactionAttempts++;
  const timeoutCompactResult = await compactContextEngineWithSafetyTimeout(contextEngine, ...);   // 1795
  if (timeoutCompactResult.compacted) {
    adoptCompactionTranscript(timeoutCompactResult);
    autoCompactionCount += 1;
    postCompactionGuard.armPostCompaction();
    continue;   // 压缩后重试
  }
}
```

最多执行 `MAX_TIMEOUT_COMPACTION_ATTEMPTS = 2` 次。

#### ④ Context Overflow Compaction（1847–2134）

检测到 `contextOverflowError`（来自 `promptError` 或 `assistantErrorText`）后，分三种子路径：

```
a. SDK 内部已 auto-compacted（attemptCompactionCount > 0）
   → overflowCompactionAttempts++ ; continue（最多 3 次，行 1890–1902）

b. 未 auto-compacted → 触发显式 overflow compaction（行 1918–2069）
   → contextEngine.compact(force=true) → 成功则 continue

c. 有超大 tool result → truncateOversizedToolResultsInSession（行 2075–2116）
   → 截断后 continue

d. compaction 失败 / 次数耗尽 → return 上下文溢出错误 payload（行 2134）
```

#### ⑤ Codex App-Server Client Close 重试（2193–2214）

```ts
if (attempt.codexAppServerClientClosed && !alreadyRetried) {
  suppressNextUserMessagePersistence = true;
  continue;   // 仅重试一次
}
```

#### ⑥ promptError 处理（2217–2469）

```
promptError（模型 API 调用在 prompt submission 阶段失败）

├─ auth 刷新成功 → authRetryPending = true; continue（行 2247）
├─ role ordering error → return 错误 payload（行 2256）
├─ image size error → return 错误 payload（行 2297）
├─ thinking level 不支持 → 降级 thinkLevel 重试（行 2419–2428）
├─ rate_limit → 尝试 rotate_profile（行 2353–2395）
│    ├─ 轮换成功 → continue
│    └─ 轮换失败且达到 cap → throw FailoverError（上层 runWithModelFallback 接管）
├─ fallback_model 决策 → throw FailoverError（行 2446）
└─ surface_error → throw promptError（行 2469）
```

#### ⑦ assistantError 处理（2472–2660）

```
assistantError（模型调用成功但 assistant response 有错误）

├─ thinking level 降级 → thinkLevel = fallbackThinking; continue（行 2477–2482）
├─ handleAssistantFailover()（行 2573）
│    ├─ action === "retry"（rotate_profile / same_model_idle_timeout）
│    │    └─ continue（行 2631）
│    └─ action === "throw" → throw FailoverError（行 2660）
│         （上层 runWithModelFallback 接管，尝试切换 model/provider）
```

---

### 5.8 成功路径（2662–3348）

到达此处说明 attempt 无致命错误，但还需经过多个 "软重试" 检查：

#### ① 构建 agentMeta & payload（2662–2715）

```ts
const agentMeta: EmbeddedPiAgentMeta = { sessionId, provider, model, usage, compactionCount, ... };   // 2673
const payloads = buildEmbeddedRunPayloads({ assistantTexts, toolMetas, ... });   // 2690
const payloadsWithToolMedia = mergeAttemptToolMediaPayloads({ payloads, toolMediaUrls, ... });   // 2716
```

#### ② Timeout 部分回复处理（2775–2840）

```ts
if (timedOutDuringPrompt && !hasSuccessfulFinalAssistantAfterPromptTimeout) {
  return { payloads: [...toolPayloads, { text: timeoutText, isError: true }], meta };   // 2807
}
```

超时但最终助手 response 已完成（stopReason = "end_turn"/"stop"）→ 使用已完成的 reply，不报超时错误。

#### ③ planning-only retry（2865–2940）

```ts
if (nextPlanningOnlyRetryInstruction && planningOnlyRetryAttempts < maxPlanningOnlyRetryAttempts) {
  planningOnlyRetryInstruction = nextPlanningOnlyRetryInstruction;
  planningOnlyRetryAttempts++;
  continue;   // 注入"请执行，不要只规划"指令重试
}
```

模型只返回了计划文字、没有执行任何 tool，触发 planning-only retry。

#### ④ reasoning-only retry（2942–2954）

```ts
if (!nextPlanningOnlyRetryInstruction && nextReasoningOnlyRetryInstruction
    && reasoningOnlyRetryAttempts < maxReasoningOnlyRetryAttempts) {
  reasoningOnlyRetryInstruction = nextReasoningOnlyRetryInstruction;
  continue;   // 注入"给出可见回答"指令重试
}
```

模型只输出了 thinking block，没有给用户可见回答。

#### ⑤ empty response retry（2960–2973）

```ts
if (!nextPlanningOnlyRetryInstruction && !nextReasoningOnlyRetryInstruction
    && nextEmptyResponseRetryInstruction && emptyResponseRetryAttempts < maxEmptyResponseRetryAttempts) {
  emptyResponseRetryAttempts++;
  continue;
}
```

模型回了空字符串，注入"请给出回答"指令重试。

#### ⑥ compaction continuation retry（2983–3004）

```ts
if (attemptCompactionCount > 0 && payloadCount === 0 && !aborted && !timedOut
    && compactionContinuationRetryAttempts < 1) {
  compactionContinuationRetryAttempts++;
  compactionContinuationRetryInstruction = COMPACTION_CONTINUATION_RETRY_INSTRUCTION;
  continue;   // compaction 打断了最终回复，从压缩后 transcript 继续
}
```

#### ⑦ silent-error retry（3152–3171）

```ts
if (sessionLastAssistant?.stopReason === "error" && outputTokens === 0 && contentEmpty
    && !hadPotentialSideEffects && emptyErrorRetries < MAX_EMPTY_ERROR_RETRIES) {
  emptyErrorRetries++;
  continue;   // 无输出 + error stopReason，直接重提（最多 3 次）
}
```

#### ⑧ reasoning-only retries exhausted（3068–3119）

```ts
if (reasoningOnlyRetriesExhausted && !finalAssistantVisibleText) {
  return { payloads: [{ text: "⚠️ Agent couldn't generate a response.", isError: true }] };   // 3089
}
```

#### ⑨ strict-agentic blocked（3013–3066）

```ts
if (!incompleteTurnText && nextPlanningOnlyRetryInstruction && strictAgenticActive) {
  return { payloads: [{ text: STRICT_AGENTIC_BLOCKED_TEXT, isError: true }] };   // 3036
}
```

strict-agentic 合约下 planning-only retries 耗尽，终止。

#### ⑩ incomplete turn error（3173–3231）

```ts
if (incompleteTurnText) {
  await maybeMarkAuthProfileFailure(...);   // 将当前 profile 标为 cooldown
  return { payloads: [{ text: incompleteTurnText, isError: true }] };   // 3201
}
```

#### ⑪ 正常成功 return（3234–3348）

```ts
await markAuthProfileSuccess({ store: profileFailureStore, profileId: lastProfileId, ... });   // 3238
return {
  payloads: terminalPayloads,
  meta: {
    durationMs, agentMeta, aborted,
    finalAssistantVisibleText, finalAssistantRawText,
    replayInvalid, livenessState, stopReason,
    executionTrace: { winnerProvider, winnerModel, attempts, fallbackUsed },
    requestShaping: { authMode, thinking, reasoning, verbose },
    toolSummary, completion, contextManagement,
    ...
  },
  messagingToolSentTexts, successfulCronAdds, acceptedSessionSpawns,
};
```

---

## 六、finally 清理（3350–3389）

无论成功还是失败，**必然执行**：

| 行号 | 操作 |
|------|------|
| 3351 | `forgetPromptBuildDrainCacheForRun(runId)` — 清理 prompt build 缓存 |
| 3352 | `stopRuntimeAuthRefreshTimer()` — 停止 OAuth token 自动刷新定时器 |
| 3353–3361 | `contextEngine.dispose()` — 释放 context engine 连接/资源 |
| 3362–3387 | `retireSessionMcpRuntime` — 回收本次 run 使用的 bundle MCP 运行时（若 `cleanupBundleMcpOnRunEnd === true`） |

---

## 流程全图

```
runEmbeddedPiAgent(params)
│
├─ [入队前] backfillSessionKey / lane / timeout / abortCheck
│
├─ enqueueSession
│   └─ enqueueGlobal
│       │
│       ├─ [Startup] workspace → plugins → hook → harness → model → auth → contextEngine
│       │
│       ├─ [初始化] retry 计数器、compaction 计数器、replay state
│       │
│       └─ while (true)   ← 主循环
│           │
│           ├─ [检查] runLoopIterations >= MAX → 返回 retry limit error
│           │
│           ├─ [组装] prompt + retry instructions
│           ├─ [构建] runtimePlan（provider/model/auth/thinking）
│           ├─ [调用] runEmbeddedAttemptWithBackend → 流式 LLM + Tool Call
│           │
│           ├─ [结果] normalizeEmbeddedRunAttemptResult
│           ├─ [熔断] idle timeout breaker
│           │
│           ├─ [恢复] preflightRecovery         → continue
│           ├─ [恢复] LiveSessionModelSwitch    → throw LiveSessionModelSwitchError
│           ├─ [恢复] timeout compaction        → contextEngine.compact → continue
│           ├─ [恢复] context overflow          → compact / truncate / return error
│           ├─ [恢复] promptError               → auth refresh / profile rotate / throw FailoverError
│           ├─ [恢复] assistantError            → thinking降级 / profile rotate / throw FailoverError
│           │
│           ├─ [软重试] planning-only           → inject instruction, continue
│           ├─ [软重试] reasoning-only          → inject instruction, continue
│           ├─ [软重试] empty response          → inject instruction, continue
│           ├─ [软重试] compaction continuation → inject instruction, continue
│           ├─ [软重试] silent-error            → bare resubmit, continue
│           │
│           ├─ [终止] timeout error / strict-agentic blocked / reasoning exhausted / incomplete turn
│           │
│           └─ [成功] markAuthProfileSuccess → return EmbeddedPiRunResult
│
└─ finally: dispose contextEngine / retire MCP / stop auth timer
```
