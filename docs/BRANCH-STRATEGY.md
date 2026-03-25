# 分支管理策略

## 分支模型

```
mobile        ← 主干分支，稳定可发布
  ↑ PR
feat/*        ← 功能分支，每个功能一个
fix/*         ← 修复分支
release/*     ← 发版分支
```

## 分支命名规范

- `feat/<模块>-<功能>` — 新功能，例：`feat/practice-auto-play`
- `fix/<模块>-<问题>` — 修 bug，例：`fix/score-pagination-crash`
- `release/<版本号>` — 发版，例：`release/v1.1.0`
- `hotfix/<描述>` — 紧急修复

## 合入标准（必须全部满足）

1. **一次提交只解决一个问题** — commit 粒度小，职责单一
2. **经测试-Roy 验证通过** — PR 中需附测试结果或验收记录
3. **提交记录与实际代码一致** — commit message 准确描述改动内容
4. **Wiki/README 同步更新** — 文档与代码保持同步

## PR 流程

1. 从 `mobile` 拉 feature 分支
2. 开发完成后提交 PR → `mobile`
3. PR 描述使用模板，填写改动说明
4. 等待测试-Roy 验证
5. CMO-Palm 审核合入标准
6. 合入 `mobile`，删除 feature 分支

## 责任人

- **分支管控 & 合入审核**：CMO-Palm
- **测试验证**：测试-Roy
- **各 feature 开发**：对应模块负责人
