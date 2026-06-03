---
name: kb-{{KB_ID}}
description: 查询「{{KB_DISPLAY_NAME}}」——{{KB_DOMAIN}}的事实问答
version: "1.0"
metadata: { "openclaw": { "requires": { "bins": ["kb-cli"] } } }
tools:
  - kb-cli
---

# {{KB_DISPLAY_NAME}}检索

## 参考文件
以下文件是本知识库的原始资料，路径相对于本 SKILL.md 所在目录：
{{REFERENCE_FILES}}

需要引用原文时，用 read 工具读取对应文件。

## 权限边界
当前 OPT 拥有：{{KB_PERMISSION}}（只读检索）
本知识库不支持写入；遇到"修改"类请求，告知用户联系管理员。

## 何时使用
- 用户问{{KB_DOMAIN}}类事实问题
- 需要引用权威条款作答时
- 不用于：结构化关系查询（走 ontology-* SKILL）

## 命令格式
```bash
kb-cli search --kb {{KB_ID}} --query "<问题>" --topk 5 --json
kb-cli get --kb {{KB_ID}} --doc-id <id> --json
```

## 执行纪律
- 优先用 kb-cli 语义检索；不足时用 read 工具读参考文件补充
- 答案必须基于检索片段或参考文件原文，标注来源，不凭记忆编造
- 召回为空时如实说"未找到"，不杜撰
