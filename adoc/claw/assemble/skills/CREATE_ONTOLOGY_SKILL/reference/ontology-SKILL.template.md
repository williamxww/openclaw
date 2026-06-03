---
name: ontology-{{ONTO_ID}}
description: 查询「{{ONTO_DISPLAY_NAME}}」——{{ONTO_DOMAIN}}的结构化关系
version: "1.0"
metadata: { "openclaw": { "requires": { "bins": ["onto-cli"] } } }
tools:
  - onto-cli
---

# {{ONTO_DISPLAY_NAME}}查询

## 权限边界
当前 OPT 拥有：{{ONTO_PERMISSION}}（只读）
本体只读，不支持改写概念 / 关系。

## 何时使用
- 需要结构化关系：{{ONTO_DOMAIN}}
- 需要概念定义和属性时
- 不用于：原文事实问答（走 kb-* SKILL）

## 命令格式
```bash
onto-cli concept get   --onto {{ONTO_ID}} --name "<概念>" --json
onto-cli relation list --onto {{ONTO_ID}} --entity "<实体>" --rel "<关系>" --json
onto-cli query         --onto {{ONTO_ID}} --expr "<查询表达式>" --json
```

## 执行纪律
- 关系遍历的结论附上来源实体和关系名，不臆断未声明的关系
- 查不到对应概念 / 关系时如实说明，不编造
