---
name: nl2sql
description: 把自然语言查询转换为 Spark SQL 并通过 water-cli 对数仓执行只读查询
version: "1.0"
metadata: { "openclaw": { "requires": { "bins": ["water-cli"] } } }
tools:
  - nl2sql
---

# NL2SQL Skill

把用户的自然语言数据查询需求转换为 Spark SQL，通过 `water-cli sql exec` 执行**只读**查询。

## 何时使用
- 用户用自然语言提出数仓数据查询（"查上个月各渠道的订单量"）
- 需要从 schema 推断字段、生成 SQL 时
- 不用于：DDL/DML 写操作；schema 结构查询走 `water-cli schema get/search`

## 执行流程（严格按序）

### Step 1：先搜索相关表
不确定表名时，先语义搜索召回候选表：
```bash
water-cli schema search <业务关键词> --format json
```

### Step 2：确认表结构
确定目标表后，查字段口径：
```bash
water-cli schema get <namespace> <table> --format json
```
字段名、分区字段、时间字段以此为准，不凭记忆。

### Step 3：生成 SQL
根据 schema 信息，将自然语言转为 Spark SQL。生成规则：
- 默认加 `LIMIT 1000`（除非用户显式要求全量）
- 时间过滤优先用分区字段，避免全表扫描
- 只生成 SELECT；涉及写操作一律拒绝

### Step 4：回显 SQL，等用户确认（可选）
复杂查询或涉及大表时，先把 SQL 展示给用户确认再执行。

### Step 5：执行
```bash
# 默认 Markdown 输出（适合直接阅读）
water-cli sql exec "<SQL>"

# JSON 输出（适合结构化解析）
water-cli sql exec "<SQL>" --format json

# CSV 导出
water-cli sql exec "<SQL>" --format csv > workspace/output/result.csv
```

## 执行纪律
- 生成的 SQL 必须回显给用户，不黑盒执行
- 默认加 `LIMIT 1000`；用户要全量时，先提示扫描代价（行数/分区数）再执行
- 全表扫描 / 无分区过滤 / 跨库大 join，先提示代价
- 回报时附：结论 + 数据 + 实际执行的 SQL + 口径说明（时间范围、过滤条件、聚合粒度）

## 输出格式示例（--format json）
```json
{
  "sql": "SELECT channel, COUNT(*) AS order_cnt FROM ods.ods_order_detail WHERE dt BETWEEN '2026-04-01' AND '2026-04-30' GROUP BY channel LIMIT 1000",
  "rows": [
    { "channel": "app", "order_cnt": 12345 },
    { "channel": "web", "order_cnt": 6789 }
  ],
  "rowCount": 2,
  "truncated": false
}
```

## 注意事项
- 时间口径以表的分区/时间字段为准，跨时区按 Asia/Shanghai
- 查询账号只读，任何写意图一律拒绝并提示走创建类流程
