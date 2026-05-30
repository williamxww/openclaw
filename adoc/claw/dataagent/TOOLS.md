# TOOLS.md

> 本文件只记录本环境的连接信息与命令约定，不控制工具开关（工具可用性由 openclaw.json 决定）。
> 占位值（`<...>`）请按实际环境填写。

## CLI 工具：water-cli

数据平台统一命令行工具，所有查询类操作通过 `water-cli` 执行。
- 默认输出：Markdown（含本体 annotations、字段列表、FK）
- 脚本/agent 解析：加 `--format json`
- CSV 导出：加 `--format csv`

## Schema / 本体 / 数据查询（只读）

### 语义搜索本体 + 召回相关表
```bash
water-cli schema search <关键词> [关键词...]
water-cli schema search 订单 用户 --max-results 10
water-cli schema search 订单 --format json
```
输出含：本体节点 annotations、相关表字段列表、外键关系（FK）。
**用途：** 不知道表名时先 search，再 get 精确查。

### 查单张表结构
```bash
water-cli schema get <namespace> <table>
water-cli schema get ods ods_order_detail
water-cli schema get ods ods_order_detail --format json
```
输出：字段名、类型、注释、分区字段、主键/外键。

### 执行 Spark SQL（只读查询）
```bash
water-cli sql exec "<SQL>"
water-cli sql exec "select * from ods.ods_order_detail limit 10"
water-cli sql exec "select 1 as n" --format json
water-cli sql exec "select * from ads.report" --format csv > report.csv
```
执行引擎：Spark SQL，支持跨库查询。

## 创建类操作（写操作，需 Approval gate）
- 创建外部数据源：`water-cli datasource create --spec <file.json> --format json`
- 创建采集任务：`water-cli collect create --spec <file.json> --format json`
- 创建稽核任务：`water-cli audit create --spec <file.json> --format json`
- 创建加工工作流：`water-cli pipeline create --spec <file.json> --format json`
- 以上命令支持 `--dry-run` 预览，创建前一律先 `--dry-run` 给用户看

## 注意事项
- 查询账号只读，禁止对生产数仓直接 INSERT/UPDATE/DELETE/DDL
- `sql exec` 执行前自动在 SQL 末尾加 `LIMIT` 保护（除非用户显式要求全量）
- 创建类操作的 spec 文件先写到 `workspace/specs/`，确认后再提交
- 所有创建结果（数据源 ID / 任务 ID / 工作流 ID）回写到 `memory/YYYY-MM-DD.md`
