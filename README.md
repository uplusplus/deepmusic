# DeepMusic – Your Music AI Assistant

> DeepMusic is redefining how humans learn music, create music, and perform music.

---

## 产品概述

DeepMusic 是 AI 驱动的音乐学习助手，Phase 1 聚焦**钢琴学习**。通过蓝牙 MIDI 数字钢琴连接，提供实时乐谱跟随、练习评估和智能曲谱库。

### 核心功能

- 🎹 **蓝牙 MIDI 连接** — 连接 Yamaha P125 等数字钢琴
- 📖 **智能乐谱跟随** — 实时跟踪弹奏位置，自动翻页
- 🎯 **练习评估** — 音准 + 节奏多维评分（S/A/B/C/D/F）
- 🎼 **曲谱库** — 30 首无版权曲谱，分类筛选
- 👤 **用户系统** — 注册/登录、练习历史、收藏

### 平台

| 平台 | 状态 |
|------|------|
| Android | ✅ Phase 1 |
| iOS | ✅ Phase 1 (需 macOS) |
| HarmonyOS | ⏳ Phase 2 |

---

## 技术栈

| 层级 | 技术 |
|------|------|
| 移动端 | Flutter 3.x + Riverpod |
| 后端 | Express + TypeScript + Prisma |
| 数据库 | SQLite (dev) / PostgreSQL (prod) |
| MIDI | flutter_midi_command (BLE MIDI) |
| 乐谱渲染 | OpenSheetMusicDisplay (WebView) |

---

## 快速开始

### 后端

```bash
cd server
npm install
cp .env.example .env
npm run db:generate && npm run db:migrate && npm run db:seed
npm run scores:import
npm run dev
# → http://localhost:3000/health
```

### 移动端

```bash
cd mobile
flutter pub get
flutter run
```

详细配置参见 [SETUP.md](docs/SETUP.md)。

---

## 项目结构

```
deepmusic/
├── docs/                  # 设计文档
│   ├── PRD.md             # 产品需求
│   ├── ARCHITECTURE.md    # 技术架构
│   ├── ROADMAP.md         # 开发路线图
│   └── SETUP.md           # 环境配置
├── mobile/                # Flutter 移动端
│   └── lib/
│       ├── core/          # 基础设施 (主题/路由/常量)
│       ├── features/      # 功能模块 (home/midi/score/practice/profile)
│       ├── shared/        # 共享组件
│       └── data/          # 数据层 (仓库/数据源/模型)
├── server/                # Express 后端
│   ├── src/
│   │   ├── routes/        # API 路由 (auth/scores/practice/devices)
│   │   ├── services/      # 业务逻辑
│   │   └── middleware/    # 中间件 (验证/错误/404)
│   └── prisma/            # 数据模型 + 迁移
```

---

## 开发进度

### ✅ 已完成
- [x] 产品需求文档 (PRD)
- [x] 技术架构设计
- [x] 开发路线图
- [x] Flutter 项目结构 + 核心模块框架
- [x] Express 后端 API (Auth/Score CRUD)
- [x] Prisma 数据模型 (Score/User/PracticeRecord/Tag/Device)
- [x] 30 首无版权乐谱数据导入
- [x] 乐谱上传 (MusicXML) + Multer 文件处理
- [x] Dart 数据模型 (Score/Note/Measure/Part)
- [x] ScoreFollower / NoteEvaluator / MidiService 初稿

### ⏳ 进行中
- [ ] MusicXML 解析器实现
- [ ] OSMD 乐谱渲染集成
- [ ] 蓝牙 MIDI 底层实现

### 📋 待开发
- [ ] 后端练习 API (practice routes)
- [ ] ScoreFollower 容错 + 和弦支持
- [ ] 用户注册/登录 UI
- [ ] 练习历史 & 统计
- [ ] 端到端测试
- [ ] App 发布

---

## 文档

- [PRD — 产品需求文档](docs/PRD.md)
- [ARCHITECTURE — 技术架构](docs/ARCHITECTURE.md)
- [ROADMAP — 开发路线图](docs/ROADMAP.md)
- [SETUP — 环境配置](docs/SETUP.md)

---

*项目启动: 2026-03-15 | 最近更新: 2026-03-20*
