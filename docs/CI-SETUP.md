# CI & Pre-commit Setup

## CI Pipelines

GitHub Actions 自动运行，触发条件：
- **push** 到 `develop` 或 `main`
- **PR** 到 `develop` 或 `main`

### Flutter 移动端 (`ci-mobile.yml`)
| Job | 命令 | 说明 |
|-----|------|------|
| Analyze | `flutter analyze --no-fatal-infos` | 代码静态分析 |
| Test | `flutter test --coverage` | 单元测试 + 覆盖率 |
| Build | `flutter build apk --debug` | 确保编译通过 |

### Express 后端 (`ci-server.yml`)
| Job | 命令 | 说明 |
|-----|------|------|
| Lint | `npm run lint` | ESLint 检查 |
| Typecheck | `npx tsc --noEmit` | TypeScript 类型检查 |
| Test | `npm test` | Jest 测试 |

## Pre-commit Hook

使用 **husky + lint-staged**，提交前自动检查改动文件。

### 初始化（新克隆仓库后执行）

```bash
# 根目录
npm install

# Server
cd server && npm install

# Mobile
cd mobile && flutter pub get
```

### 配置说明

- `.husky/pre-commit` — 触发 `lint-staged`
- `.lintstagedrc.js` — 按文件类型匹配检查规则
  - `server/src/**/*.ts` → ESLint fix + TypeScript check
  - `mobile/lib/**/*.dart` → dart format + flutter analyze
- 根目录 `package.json` — husky 的 `prepare` 脚本

## PR 模板

`.github/pull_request_template.md` — PR 提交时自动填充，包含变更类型、影响范围、测试 checklist。

## 文件清单

```
.github/
├── workflows/
│   ├── ci-mobile.yml          # Flutter CI
│   └── ci-server.yml          # Express CI
└── pull_request_template.md   # PR 模板

.husky/
└── pre-commit                 # pre-commit hook

.lintstagedrc.js               # lint-staged 配置
package.json                   # husky + lint-staged 依赖
```
