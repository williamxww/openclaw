# Agent 装配方案（数字员工）

---

## 一、文件全景


### 多 Agent（数字员工场景）

**每个子 agent 有完全独立的 workspace 目录**，不是在同一个 workspace 下建子文件夹。目录结构是平级的：

```
~/.openclaw/
├── openclaw.json              ← 全局配置（模型/工具/MCP/技能/agent 路由）  声明所有 agent 及其 workspace 路径   
├── skills/                    ← 多 agent 共享的 managed skills
└── agents/
    ├── main/
        └── agent/
        │   └── auth-profiles.json   ← main agent 独立的模型 auth
        └──  sessions   -- 历史记录

~/workspaces/                  ← 自定义位置，统一管理多个 workspace
├── main/                   ← agent "main" 的 workspace
│   ├── AGENTS.md
│   ├── SOUL.md
│   ├── IDENTITY.md
│   ├── USER.md
│   ├── TOOLS.md
│   ├── HEARTBEAT.md
│   ├── MEMORY.md
│   ├── memory/
│   ├── skills/                ← main 专属 skill
│   └── workflows/             ← main 的 Lobster 工作流文件
├── hr/                        ← agent "hr" 的 workspace
│   ├── AGENTS.md
│   └── ...
└── finance/                       ← agent "finance" 的 workspace
    ├── AGENTS.md
    └── ...


```

在 `openclaw.json` 中声明多 agent 及其 workspace：

```json5
{
  "agents": {
    "defaults": {
      // 若不指定 workspace，默认 ~/.openclaw/workspace
    },
    "list": [
      {
        "id": "finance",
        "workspace": "~/workspaces/finance",
        "executionContract": "strict-agentic"
      },
      {
        "id": "hr",
        "workspace": "~/workspaces/hr"
      },
      {
        "id": "dataagent",
        "workspace": "~/workspaces/dataagent",
        "agentDir": "/root/.openclaw/agents/dataagent/agent",
        "skills": ["nl2sql"]
      }
    ]
  },
  "models": {
    "mode": "merge",
    "providers": {
      "custom-10-69": {
        "baseUrl": "http://10.69.xxxx/v1",
        "api": "openai-completions",
        "apiKey": "",
        "models": [
          {
            "id": "qwen3.5-35b",
            "name": "qwen3.5-35b (Custom Provider)",
            "contextWindow": 128000,
            "maxTokens": 4096,
            "input": [
              "text"
            ],
            "reasoning": false
          }
        ]
      }
    }
  }
}
```


> **关键点：**
> - 每个 agent 的 workspace 是**完全隔离的独立目录**，平级而非嵌套
> - `~/.openclaw/agents/<agentId>/` 存放该 agent 的 auth、session 等状态，**不是** workspace
> - workspace 里的 `skills/` 是该 agent 私有的（最高优先级）
> - `~/.openclaw/skills/` 是所有 agent 共享的 managed skills
> - **不要复用 `agentDir`**（即 `~/.openclaw/agents/<id>/`），否则 auth/session 会冲突

---

## 二、各文件职责与内容规范

### `AGENTS.md` — 操作规则核心

**每次 session 启动时自动注入**，是 agent 行为约束的主要来源。

**应包含：**

```markdown
## 角色定位
（这个数字员工是谁、属于哪个业务域、核心职责）

## Session 启动
- 读取 runtime 提供的上下文（AGENTS.md / SOUL.md / USER.md 已自动注入）
- 仅在上下文缺失时手动重读

## memory规则
- 日志写 memory/YYYY-MM-DD.md
- 重要决策/教训写 MEMORY.md
- 不允许"脑记"，必须落文件

## Standing Orders（常驻任务）
### Program: <业务流程名>
**Authority:** 可自主执行的范围
**Trigger:** 触发方式（定时 cron / 事件 / 手动）
**Approval gate:** 需要人工确认的操作
**Escalation:** 何时停下来请示

#### 执行步骤（严格按序）
1. 步骤一 — 用什么工具、预期产出
2. 步骤二 — ...
3. ...

#### 执行规则
- 每步必须：执行 → 验证结果 → 上报状态
- 任何步骤失败：立即停止，报告失败，不跳过继续
- 最多重试 2 次，仍失败则升级
- 不允许只返回计划，必须实际执行

## 红线（绝对禁止）
- 不得泄露私有数据
- 不得在未确认前执行破坏性操作
- 外发行为（邮件/消息/Post）必须经过 Approval gate

```

---

### `SOUL.md` — 人格与语气

**每次 session 注入**，影响 agent 的表达方式和边界感。

**应包含：**

```markdown
# SOUL.md

## 核心气质
- 语气风格（严肃/活泼/简洁/专业）
- 是否允许表达意见/异议
- 简洁原则（能一句话说清就不要三句）

## 边界
- 私有信息保密原则
- 不确定时先问再做
- 外发消息谨慎，内部操作大胆

## Vibe
（一两句描述这个 agent 的整体感觉，比如：
"你是一个务实的财务助手。直接、精准、不废话。出错就说出错，不掩饰。"）
```

> 注意：**不要**在 SOUL.md 里放操作规则。操作规则在 AGENTS.md。SOUL.md 只管"怎么说话"。

---

### `IDENTITY.md` — 名字与定位

**包含：**

```markdown
# IDENTITY.md

- **Name:** 小财（示例）
- **Role:** 财务数字员工
- **Vibe:** 严谨、高效、务实
- **Emoji:** 💼
- **Avatar:** avatars/caiwu.png（可选）

## 职责范围
（一段话：这个 agent 是做什么的，不是做什么的）
```

---

### `USER.md` — 用户画像

告诉 agent "它在服务谁"，影响沟通方式和权限边界。

**包含：**

```markdown
# USER.md

- **Name:** 张三
- **Role:** 财务总监
- **Preferred address:** 张总
- **Timezone:** Asia/Shanghai
- **Language:** 中文优先
- **Notes:**
  - 偏好简洁汇报，不需要过多解释
  - 对数据准确性要求极高
  - 审批权限：单笔 ≤ 10000 元可自动执行，超过需确认
```

---

### `TOOLS.md` — 本地工具约定

**不控制工具可用性**（那是 openclaw.json 的事），只记录本环境特有的配置信息。

**包含：**

```markdown
# TOOLS.md

## 数据库
- 财务数据库：finance-db.internal:5432 / user: readonly_agent
- 报表输出目录：/data/reports/finance/

## API 端点
- 订单系统：http://order-api.internal/v2
- OA 系统：http://oa.internal/api

## 常用命令别名
- 账单检查：`finance-cli check --json`
- 月报生成：`finance-cli report --month YYYY-MM --json`

## 注意事项
- 所有写操作需要走 approval gate
- finance-db 只读，不得直接 INSERT/UPDATE
```

---

### `HEARTBEAT.md` — 周期检查清单

**心跳触发时（约每 30 分钟）** agent 读取此文件执行。保持**极短**，避免 token 浪费。

**包含：**

```markdown
# HEARTBEAT.md

## 周期检查（每次心跳轮流执行 2-3 项）

- [ ] 检查是否有待处理的审批请求
- [ ] 检查订单系统是否有异常告警
- [ ] 检查今日报表是否已生成
- [ ] 检查邮件：是否有需要转人工的紧急事项

## 主动上报条件
- 发现异常才通知，无异常返回 HEARTBEAT_OK
- 深夜（23:00-08:00）除非紧急否则静默
```

> 提示：把多个周期检查合并进心跳，比创建多个 cron 更省 API 调用。精确定时用 cron，周期批量检查用心跳。

---

### `BOOTSTRAP.md` — 首次启动仪式

**仅用于全新工作区的首次初始化**，完成后**删除此文件**。

对于数字员工场景，建议**跳过对话式初始化**，改为预填充所有文件，直接删除 BOOTSTRAP.md 或在 openclaw.json 中禁用：

```json5
{
  "agents": { "defaults": { "skipBootstrap": true } }
}
```


---

## 三、SKILL 装载位置

### 优先级顺序（高 → 低）

```
1. <workspace>/skills/<skill-name>/SKILL.md      ← 最高，工作区私有
2. <workspace>/.agents/skills/<skill-name>/       ← 工作区 project agent skills
3. ~/.agents/skills/<skill-name>/                 ← 个人 agent skills
4. ~/.openclaw/skills/<skill-name>/               ← managed skills（CLI 安装）
5. 内置 bundled skills                            ← OpenClaw 自带
6. skills.load.extraDirs（openclaw.json 配置）    ← 最低
```

### 推荐位置

| 场景 | 推荐路径 |
|------|---------|
| 该数字员工专属 skill | `<workspace>/skills/<skill-name>/` |
| 多个 agent 共享 skill | `~/.openclaw/skills/<skill-name>/` 或 extraDirs |
| 来自 ClawHub 安装 | `~/.openclaw/skills/`（CLI 自动管理） |

### 在 `openclaw.json` 中配置

```json5
{
  "skills": {
    "load": {
      // 额外扫描目录（最低优先级）
      "extraDirs": ["~/company-skills/"],
      // 允许工作区 skills/ 目录下的 symlink 指向此路径
      "allowSymlinkTargets": ["~/Projects/shared-skills"],
      "watch": true
    },
    "entries": {
      // 启用/禁用特定 skill，并注入环境变量
      "finance-check": { "enabled": true },
      "order-query": {
        "enabled": true,
        "env": { "ORDER_API_KEY": "your-key" }
      },
      "sag": { "enabled": false }
    },
    // 仅允许这些 bundled skills（不影响 workspace/managed skills）
    "allowBundled": ["brave-search"]
  },
  "agents": {
    "defaults": {
      // 默认所有 agent 只能使用这些 skills
      "skills": ["finance-check", "order-query"]
    },
    "list": [
      { "id": "main" },                           // 继承 defaults
      { "id": "analyst", "skills": ["finance-check", "brave-search"] },  // 覆盖
      { "id": "restricted", "skills": [] }        // 无 skill
    ]
  }
}
```

### SKILL.md 文件格式

```markdown
---
name: finance-check
description: 检查财务数据和生成报表
version: "1.0"
tools:
  - finance-check
---

# Finance Check Skill

（使用说明：agent 读取此 SKILL.md 了解如何调用该工具）

## 何时使用
- 需要检查账单异常时
- 生成月报/周报时

## 命令格式
\`\`\`bash
finance-cli check --json           # 检查异常
finance-cli report --month 2026-05 # 生成月报
\`\`\`

## 输出格式
（JSON 结构说明）
```

---

## 四、MCP 配置位置

MCP 统一配置在 `~/.openclaw/openclaw.json` 的 `mcp.servers` 下，**不需要改代码**。

### 配置结构

```json5
{
  "mcp": {
    "servers": {
      // stdio 类型：本地进程
      "context7": {
        "command": "uvx",
        "args": ["context7-mcp"]
      }
    },
    // MCP 会话闲置超时（毫秒），0 = 不超时
    "sessionIdleTtlMs": 600000
  }
}
```

---

## 五、工作流适配方案

### 方案选型矩阵

| 需求 | 推荐方案 | 文件/配置位置 |
|------|---------|-------------|
| 定义 agent 能做什么、步骤规范 | Standing Orders | `AGENTS.md` |
| 强制 agent 必须执行（不能只说不做） | strict-agentic | `openclaw.json` |
| **严格按节点执行的确定性工作流** | **Lobster** | `.lobster` 文件 |
| 多步骤跨 session 持久化 | Task Flow | CLI 管理 |
| 精确定时触发 | Cron Job | CLI 配置 |
| 批量周期检查 | Heartbeat | `HEARTBEAT.md` |

---

### 方案一：Standing Orders（轻量，靠 prompt 约束）

在 `AGENTS.md` 中定义业务流程节点：

```markdown
## Program: 订单日清流程

**Authority:** 自动处理 pending 状态订单
**Trigger:** 每天 09:00（由 cron 触发）
**Approval gate:** 退款金额 > ¥500 需人工确认

### 执行步骤（严格按序，不得跳过）

1. **数据拉取** — `order-cli list --status pending --json`
2. **规则校验** — `order-cli validate --json`，stdin 传入上步输出
3. **分类处理** — `order-cli categorize --json`
4. **生成报告** — 写入 `reports/orders/YYYY-MM-DD.md`
5. **发送通知** — 推送到指定渠道

### 执行纪律
- 执行 → 验证 → 上报，缺一不可
- 任何步骤失败立即停止，不继续
- 最多重试 2 次，超限升级人工
```

配合 openclaw.json 强制执行：

```json5
{
  "agents": {
    "list": [
      {
        "id": "main",
        "executionContract": "strict-agentic"
      }
    ]
  }
}
```

---

### 方案二：Lobster 工作流（强约束，引擎保证顺序）

**最适合"严格按工作流节点一步步执行"的场景。** agent 只负责触发，步骤编排由 Lobster 引擎控制，不走 LLM 推理。

#### Step 1：启用 Lobster 工具

```json5
// openclaw.json
{
  "tools": { "alsoAllow": ["lobster"] }
}
```

#### Step 2：创建 `.lobster` 工作流文件

```yaml
# workspace/workflows/order-daily.lobster
# 订单退款日清流程
# 触发方式：每日 09:00 由 cron 调起，agent 调用一次 Lobster tool call 启动
# 执行引擎：Lobster 内嵌 runner，步骤顺序由引擎保证，不经过 LLM 推理
name: order-daily-process
steps:

  # ── Step 1：数据拉取 ────────────────────────────────────────────────────────
  # 调用订单 CLI 查询当天所有 pending 状态的订单，输出 JSON 数组
  # 输出示例：[{"orderId":"ORD-001","amount":299,...}, {"orderId":"ORD-002","amount":8800,...}]
  - id: fetch
    command: order-cli list --status pending --json

  # ── Step 2：规则校验 ────────────────────────────────────────────────────────
  # 对 fetch 输出逐条校验业务规则（字段完整性、金额合法性、退款资格等）
  # stdin: $fetch.stdout 表示把上一步的 stdout 通过管道直接传入本命令的 stdin
  # 不合规订单在此被过滤，后续步骤只看到通过校验的订单
  - id: validate
    command: order-cli validate --json
    stdin: $fetch.stdout

  # ── Step 3：分类处理 ────────────────────────────────────────────────────────
  # 对通过校验的订单按退款金额、类型、来源分组
  # 分类结果会被后续 Step 4（审批预览）、Step 5（执行退款）、Step 6（报告）共同引用
  # 注意：categorize.stdout 是后续所有步骤的数据来源，不是审批步骤的输出
  - id: categorize
    command: order-cli categorize --json
    stdin: $validate.stdout

  # ── Step 4：审批门控（唯一人工介入点）──────────────────────────────────────
  # 生成退款操作的预览摘要（将要退哪些单、金额合计、高风险标记）供审批人确认
  # approval: required 让 Lobster 引擎在此暂停整个流程，返回 resumeToken 给 agent
  # agent 把预览推送给审批人，等待回复 approve / reject
  # 流程在收到 resume 调用前不会继续，gateway 重启也不丢失暂停状态
  - id: approve_large_refund
    command: order-cli preview-refunds --json
    stdin: $categorize.stdout
    approval: required

  # ── Step 5：执行退款（条件步骤）────────────────────────────────────────────
  # condition 字段：仅当 Step 4 审批结果为 approved 时本步骤才执行
  # 若审批人 reject，本步骤跳过，流程直接进入 Step 6 生成报告
  # 退款数据来自 Step 3（categorize），不来自审批步骤
  - id: execute_refund
    command: order-cli execute-refunds --json
    stdin: $categorize.stdout
    condition: $approve_large_refund.approved

  # ── Step 6：生成报告 ────────────────────────────────────────────────────────
  # 无论 Step 5 是否执行，本步骤始终运行
  # 报告内容：处理订单数、退款成功/失败/跳过明细、本次运行时间戳
  # 报告以 JSON 格式输出，传给下一步用于推送
  - id: report
    command: order-cli report --json
    stdin: $categorize.stdout

  # ── Step 7：推送通知 ────────────────────────────────────────────────────────
  # 把 Step 6 报告内容推送到 Slack #ops-alerts 频道
  # openclaw.message 是 OpenClaw 内置 messaging 工具，不需要额外安装
  # 无论退款执行与否，运营团队都能看到本次日清结果
  - id: notify
    command: openclaw.message --channel slack --to "#ops-alerts"
    stdin: $report.stdout
```

#### Step 3：在 AGENTS.md 中定义触发规则

```markdown
## Program: 订单日清流程

**Trigger:** 每天 09:00 由 cron 触发
**执行方式:** 调用 Lobster 工作流 `workflows/order-daily.lobster`
**审批:** 遇到 needs_approval 时等待人工 approve/reject
**不得:** 跳过 Lobster 直接调用 order-cli
```

#### Step 4：配置定时触发

```bash
openclaw cron add \
  --name "订单日清" \
  --cron "0 9 * * 1-5" \
  --tz "Asia/Shanghai" \
  --session session:order-agent \
  --message "执行订单日清工作流，调用 Lobster 工作流 workflows/order-daily.lobster" \
  --announce \
  --channel slack \
  --to "#ops-alerts"
```

#### 审批节点处理流程

```
Lobster 返回 needs_approval
    ↓
agent 通知审批人（通过 channel）
    ↓
审批人回复 approve/reject
    ↓
agent 调用 resume: { action: "resume", token: "...", approve: true/false }
    ↓
工作流继续执行后续步骤
```

---

### 方案三：Task Flow（跨 session 持久化）

当工作流需要**跨越多次 gateway 重启**保持进度：

```bash
# 查看所有流程状态
openclaw tasks flow list

# 查看某个流程详情
openclaw tasks flow show <flow-id>

# 取消流程（cancel 意图持久，重启后依然生效）
openclaw tasks flow cancel <flow-id>
```

Task Flow 自动跟踪 Lobster 工作流产生的子任务，无需额外配置。

---

### 推荐组合架构

```
openclaw.json
  └─ tools.alsoAllow: ["lobster"]
  └─ agents.list[].executionContract: "strict-agentic"
  └─ mcp.servers: { ... }

workspace/AGENTS.md
  └─ Standing Orders: 定义触发时机和审批边界
  └─ 执行纪律: 引用 Lobster 工作流文件

workspace/workflows/
  └─ order-daily.lobster      ← 严格步骤定义
  └─ monthly-report.lobster
  └─ alert-response.lobster

cron jobs（CLI 配置）
  └─ 定时触发 → 调用 agent → agent 触发 Lobster

Task Flow（自动）
  └─ 跟踪 Lobster 子任务，持久化跨 session 进度
```

**分工原则：**
- `AGENTS.md` — 定义**什么时候**触发**哪个**工作流，以及边界规则
- `.lobster` 文件 — 定义**如何**执行，步骤顺序、数据传递、审批节点
- `openclaw.json` — 工具权限、MCP 接入、agent 路由
- `TOOLS.md` — 环境特有的连接信息（地址/命名）

---

## 六、业务场景示例：OPC 申请

以 **OPC（One Person Company，一人有限责任公司）申请** 为例，说明业务流、OPT 划分和专家 agent 组成。

---

### 6.1 业务流程全景

```
事前辅导
  1. 政策咨询与匹配          ← 企业文员发起，办事员 OPT 响应
  2. 指导企业准备材料         ← 办事员 OPT 输出材料清单

事中核验
  3. 材料接收与审查           ← 企业提交材料，办事员 OPT 预审
  4. 工单分派与启动联审        ← 预审通过后，联合审查 OPT 接管

事中协同
  5. 跟踪联审进度与协调        ← 联合审查 OPT 辅助真实员工
  6. 汇总结果并反馈            ← 员工决策后，联合审查 OPT 上报结论

事后闭环
  7. 公示管理与异议处理        ← 归档 OPT 接管
  8. 办结归档与服务闭环        ← 归档 OPT 完成并关闭申请
```

---

### 6.2 OPT 划分

整个业务流由三个 OPT 协同完成，每个 OPT 只负责自己的节点段，**通过本体状态交接，互不感知对方内部细节**。

| OPT | 负责节点 | 触发方式 | 交接动作 |
|-----|---------|---------|---------|
| **办事员 OPT** | 节点 1–3 | 企业文员发起咨询，或新建申请单 | 预审通过 → 将 Application 状态置为 `under_review`，创建 ReviewTask |
| **联合审查 OPT** | 节点 4–6 | 检测到 `ReviewTask(status=pending)` | 员工决策后 → 将 Application 状态置为 `approved` / `rejected` |
| **归档 OPT** | 节点 7–8 | 检测到 `Application(status=approved)` | 公示完成 → 将 Application 状态置为 `closed` |

---

### 6.3 各 OPT 专家 Agent 组成

#### 办事员 OPT

面向企业文员，以网络数字员工形式对外服务。

```
办事员 OPT
├── main（Orchestrator）
│     职责：驱动本 OPT 内流程推进，决定何时完成预审并交接
│           接收企业消息，路由给对应专家，汇总结论回复企业
│
├── 政策专家
│     职责：调用知识库 SKILL（kb-opc-policy）检索适用政策
│           输出政策摘要 + 来源条款，供企业参考
│
└── 材料审查专家
      职责：对照本体 SKILL（ontology-opc-application）生成材料清单
            逐项核验企业提交材料是否齐全、格式是否合规
            输出"通过 / 缺失清单 / 格式问题"结论
```

#### 联合审查 OPT

面向真实审查员工，以辅助决策形式工作。**不代替员工做通过/驳回决定。**

```
联合审查 OPT
├── main（Orchestrator）
│     职责：接收 ReviewTask 待办，分配给专家，汇总报告
│           推送"审查摘要 + 风险清单"给真实员工，等待决策
│           收到员工结果后更新本体状态并触发后续
│
├── 材料审查专家
│     职责：深度合规审查（超出预审的实质性审查）
│           检查材料真实性、内容一致性、证照有效期
│           输出合规问题列表，按高/中/低风险分级
│
├── 财务专家
│     职责：核查企业财务数据、税务合规状态、资金来源合法性
│           识别财务造假嫌疑、异常关联交易等高风险信号
│           输出财务风险报告
│
└── 风险侦察专家
      职责：综合材料审查 + 财务审查结果，挖掘隐藏关联风险
            如：股权穿透、历史处罚记录、关联企业异常
            为员工决策提供"看不见的风险"清单
```

#### 归档 OPT

面向行政人员，执行公示和归档流程。

```
归档 OPT
├── main（Orchestrator）
│     职责：检测 Application(status=approved)，启动公示和归档流程
│           跟踪公示期，处理异议，最终关闭申请
│
├── 公示管理专家
│     职责：生成公示内容，发布到指定渠道（官网/公告板）
│           监听公示期内的异议反馈，分类处理或升级
│
└── 流程归档专家
      职责：整理申请全周期材料，生成归档包
            写入档案系统，更新 Application 状态为 closed
            发出服务闭环通知给企业
```

---

### 6.4 跨 OPT 状态流转

```
企业文员
  │ 发起咨询
  ▼
办事员 OPT（节点 1-3）
  │ 预审通过
  │ → Application.status = under_review
  │ → 创建 ReviewTask(type=joint_review, status=pending)
  ▼
联合审查 OPT（节点 4-6）         ← 真实员工介入决策
  │ 员工通过
  │ → Application.status = approved
  ▼
归档 OPT（节点 7-8）
  │ 归档完成
  │ → Application.status = closed
  ▼
  企业收到办结通知
```

> 每个 OPT 写完状态即止，不持有"下一步是谁"的知识。后续由哪个 OPT 接手，由外部系统（本体状态 + 事件触发）驱动。

---

## 七、设计器组件装配

设计器内的三类公共组件（知识库、业务本体、SKILL）以及业务流程图，均需转换为 agent 可读的文件形式才能生效。

---

### 7.1 知识库 → SKILL 自动生成

设计器为每个已挂载的知识库自动生成一个 SKILL.md，告诉 agent **何时查询、如何查询、输出是什么**。

生成的 SKILL 放入 `~/.openclaw/skills/<kb-skill-name>/` 供全部 agent 共享，或放入 `<workspace>/skills/` 只给该 agent 使用。

**自动生成的知识库 SKILL 示例：**

```markdown
---
name: kb-opc-policy
description: 查询 OPC 申请相关政策知识库
version: "1.0"
tools:
  - kb-query
---

# 知识库：OPC 政策知识库

## 何时使用
- 企业咨询申请资质条件、所需材料、办理时限时
- 需要引用具体政策条文或文件依据时
- 审查材料是否符合政策要求前，先查询对应标准

## 查询方式

\`\`\`bash
# 语义检索（推荐，适合自然语言问题）
kb-query search --kb opc-policy --q "注册资本要求" --top 5

# 精确文档检索
kb-query get --kb opc-policy --doc "企业资质认定办法2024"
\`\`\`

## 输出格式
\`\`\`json
{
  "results": [
    {
      "docId": "...",
      "title": "...",
      "excerpt": "...",
      "source": "文件名 第X条",
      "score": 0.92
    }
  ]
}
\`\`\`

## 注意事项
- 检索结果为参考依据，不是最终结论，需结合具体案例判断
- score < 0.7 的结果不得直接引用，须人工确认
- 政策有时效性，文档日期超过 1 年需提示用户核实
```

---

### 7.2 业务本体 → SKILL 自动生成

业务本体描述了业务域的实体、关系和字段结构（如"企业""申请单""审批节点"之间的关联）。设计器为每个本体自动生成 SKILL，告诉 agent **实体结构是什么、如何查询本体数据库**。

**自动生成的本体 SKILL 示例：**

```markdown
---
name: ontology-opc-application
description: OPC 申请业务本体，描述核心实体与查询方式
version: "1.0"
tools:
  - ontology-query
---

# 业务本体：OPC 申请

## 核心实体

| 实体 | 字段（关键） | 说明 |
|------|------------|------|
| Enterprise | id, name, creditCode, registeredCapital, establishDate | 申请企业 |
| Application | id, enterpriseId, status, submittedAt, materials[] | 申请单 |
| ReviewTask | id, applicationId, assignee, type, status, result | 审查任务 |
| Material | id, applicationId, type, fileUrl, checkResult | 提交材料 |
| Policy | id, version, effectiveDate, content | 适用政策 |

## 实体关系
```
Enterprise ──(1:N)──> Application
Application ──(1:N)──> ReviewTask
Application ──(1:N)──> Material
Application ──(N:1)──> Policy
```

## 查询方式

\`\`\`bash
# 查询实体（支持过滤）
ontology-query get --entity Application --filter "status=under_review" --json

# 查询关联实体
ontology-query related --entity Application --id APP-2024-001 --rel ReviewTask --json

# 更新实体状态（需 Approval gate）
ontology-query update --entity Application --id APP-2024-001 --set "status=approved" --json
\`\`\`

## 注意事项
- 所有写操作（update/delete）必须经过 Approval gate，不得直接执行
- 查询结果中 `status` 枚举值：`draft` / `submitted` / `under_review` / `approved` / `rejected`
- `creditCode` 是企业唯一标识，跨系统查询以此为准
```

---

### 7.3 业务流程图 → Agent 流程约束

设计器内的流程图（如 OPC 申请的 8 个节点）需转换为两层文件：

1. **Lobster 工作流**（`.lobster`）：定义每个节点的执行逻辑、数据传递、暂停点
2. **各 OPT 的 AGENTS.md Standing Orders**：告诉每个 OPT 负责哪些节点、触发条件和交接规则

#### 流程图 → 两层映射关系

```
设计器流程图（OPC 申请，8个节点）
        │
        ├── 办事员 OPT 负责节点 1-2（事前辅导）
        │     └── AGENTS.md Standing Orders：触发条件、交接给联合审查的条件
        │     └── workflows/opc-pre-consult.lobster：节点 1-2 的具体执行步骤
        │
        ├── 联合审查 OPT 负责节点 3-6（事中核验+协同）
        │     └── AGENTS.md Standing Orders：收到待办后启动、结果上报
        │     └── workflows/opc-joint-review.lobster：节点 3-6 的具体执行步骤
        │
        └── 归档 OPT 负责节点 7-8（事后闭环）
              └── AGENTS.md Standing Orders：收到通过结果后启动
              └── workflows/opc-archive.lobster：公示+归档执行步骤
```

#### 办事员 OPT 的 AGENTS.md Standing Orders 示例

```markdown
## Program: OPC 申请 — 事前辅导

**Authority:** 政策咨询、材料预审（不涉及写数据库）
**Trigger:** 企业文员发起咨询，或新 Application 创建事件（status=draft）
**Approval gate:** 预审通过后，向企业文员确认"已准备完整"再推进
**Escalation:** 遇到本体内无对应政策条文，停止并升级政策专家人工处理

### 执行步骤（严格按序）

1. **政策匹配** — 调用 `kb-opc-policy` SKILL，检索适用政策，输出政策摘要给企业
2. **材料清单生成** — 查询 `ontology-opc-application` 获取该类型申请所需材料列表
3. **材料预审** — 企业提交材料后，逐项核验是否齐全、格式是否合规
4. **预审结论** — 齐全则触发 Lobster 工作流 `workflows/opc-pre-consult.lobster` 中的交接步骤
   - 不通过：列出缺失清单，返回步骤 3，最多 3 轮
   - 通过：创建联合审查待办，将 Application 状态更新为 `under_review`

### 执行纪律
- 不得跳过材料预审直接推进联合审查
- 政策引用必须附带来源（文件名 + 条款）
- 所有与企业的沟通记录写入 `memory/YYYY-MM-DD.md`
```

#### 联合审查 OPT 的 AGENTS.md Standing Orders 示例

```markdown
## Program: OPC 申请 — 联合审查

**Authority:** 辅助真实员工审查，不得代替员工做通过/驳回决定
**Trigger:** ReviewTask 待办推送（type=joint_review, status=pending）
**Approval gate:** 每次审查结论必须由真实员工确认（approve / reject）
**Escalation:** 发现高风险项（财务造假嫌疑、证件疑似伪造）立即停止，标记并上报

### 执行步骤（严格按序）

1. **加载上下文** — 查询 Application + Material + Enterprise 完整信息
2. **财务合规核查** — 调用财务专家子 agent，输出财务风险报告
3. **材料深度审查** — 调用材料审查专家子 agent，输出合规问题列表
4. **风险汇总** — 合并两份报告，生成"审查摘要 + 风险清单"
5. **等待员工决策** — 推送摘要给对应真实员工，暂停等待 approve/reject
6. **执行决策** — 按员工决定更新 Application 状态，触发后续流程

### 执行纪律
- 步骤 5 必须暂停等待，不得自动决策通过
- 风险清单按严重程度排序（高/中/低），高风险项必须显式标注
```

#### Lobster 工作流示例（节点 3-4，材料接收与联审启动）

```yaml
# workspace/workflows/opc-joint-review.lobster
name: opc-joint-review
steps:

  # 节点 3：材料接收与审查
  - id: load_application
    command: ontology-query get --entity Application --filter "status=under_review" --json

  - id: financial_check
    command: agent-invoke --agent finance-expert --task "财务合规核查"
    stdin: $load_application.stdout

  - id: material_check
    command: agent-invoke --agent material-expert --task "材料合规审查"
    stdin: $load_application.stdout

  # 节点 4：工单分派与联审等待
  - id: summarize_risks
    command: risk-summarizer --json
    stdin: |
      $financial_check.stdout
      $material_check.stdout

  - id: await_employee_decision
    command: notify-employee --channel dingtalk --template joint-review-summary
    stdin: $summarize_risks.stdout
    approval: required          # 暂停，等待真实员工 approve/reject

  - id: update_status
    command: ontology-query update --entity Application --set "status=$await_employee_decision.result" --json
    condition: $await_employee_decision.completed
```

---

### 7.4 设计器生成物 → workspace 文件对应关系

| 设计器组件 | 生成物 | 放置位置 | agent 使用方式 |
|-----------|--------|---------|--------------|
| 知识库 | `kb-<name>/SKILL.md` | `~/.openclaw/skills/` 或 `<workspace>/skills/` | AGENTS.md 中 Standing Orders 引用；直接调用 `kb-query` |
| 业务本体 | `ontology-<name>/SKILL.md` | 同上 | 查询实体状态、更新实体、理解业务结构 |
| 流程图（本 OPT 负责节点） | `workflows/<flow>.lobster` | `<workspace>/workflows/` | AGENTS.md 中指定 Lobster 工作流文件路径 |
| 流程图（交接条件） | 注入到 AGENTS.md Standing Orders | `<workspace>/AGENTS.md` | 直接读取，agent 按条件决定何时交接 |
| 通知渠道 | MCP server 或 `openclaw.message` | `openclaw.json` mcp.servers | 工作流 notify 步骤直接调用 |

> **核心原则：** 设计器负责生成文件，agent 负责读文件并执行。agent 不需要知道设计器的内部结构，只需要知道自己的 workspace 里有哪些 SKILL、workflows 和 AGENTS.md 规则。

---

### 7.5 多 OPT 流转的关键约定

跨 OPT 流转依赖**本体状态**作为全局同步点，不依赖直接 agent-to-agent 调用：

```
办事员 OPT
  └─ 预审通过后：ontology-query update Application status=under_review
                 + 创建 ReviewTask(type=joint_review, status=pending)

联合审查 OPT
  └─ Heartbeat 或事件触发：检测到 ReviewTask(status=pending) → 启动工作流

归档 OPT
  └─ 检测到 Application(status=approved) → 启动归档工作流
```

**每个 OPT 只感知本体状态变化，不直接调用其他 OPT。** 这样各 OPT 解耦，任何一个 OPT 可以独立替换或升级。

> **核心原则：OPT 完全不感知后续流程。**
> 一个 OPT 完成自己的职责后，只做一件事：将处理结果写入外部系统（本体状态、工单系统、数据库）。
> 是否有后续流程、由谁接手、何时触发，由外部系统负责记录和驱动。
> 本 OPT 写完即止，不持有任何"下一步是谁"的知识。

---

