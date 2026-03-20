# DeepMusic – Your Music AI Assistant

> DeepMusic is redefining how humans learn music, create music, and perform music.

---

## 产品概述

DeepMusic 是 AI 驱动的音乐学习助手，Phase 1 聚焦**钢琴学习**。通过蓝牙 MIDI 数字钢琴连接，提供实时乐谱跟随、练习评估和智能曲谱库。

### 核心功能

- 🎹 **MIDI 连接** — 支持蓝牙 BLE 和 USB OTG 两种方式连接数字钢琴
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
| MIDI | flutter_midi_command (BLE) + usb_serial (USB OTG) |
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

**设计文档**
- [x] 产品需求文档 (PRD)
- [x] 技术架构设计
- [x] 开发路线图
- [x] 环境配置文档

**后端 API** (26 个端点，全部测试通过)
- [x] Auth: register / login / logout / me(GET) / me(PATCH)
- [x] Scores: list / recommended / search / detail / upload / update / publish / delete / xml / favorite / unfavorite
- [x] Practice: start / note / end / create / list / stats / detail / delete
- [x] Devices: list / register / update / delete / connect
- [x] User: profile(GET) / profile(PUT) / favorites / statistics
- [x] Health check
- [x] JWT 认证 + Token 黑名单 (登出失效)
- [x] 文件上传 (Multer) + MusicXML 文件下载
- [x] 收藏/取消收藏 (User-Score 多对多)
- [x] 练习会话管理 (start → note → end 流程)
- [x] Prisma 数据模型 (Score/User/PracticeRecord/Tag/Device) + 迁移
- [x] 19 首乐谱种子数据导入

**移动端核心模块**
- [x] Flutter 项目结构 + feature-based 组织
- [x] Riverpod 状态管理 + 路由配置
- [x] Dart 数据模型 (Score/Part/Measure/Note/TimeSignature/KeySignature)
- [x] MusicXML 解析器 (score-partwise 格式，含 divisions/和弦/休止符)
- [x] OSMD 乐谱渲染器 (WebView + JS Bridge 双向通信)
- [x] ScoreFollower 乐谱跟随引擎 (容错/翻页/进度流)
- [x] NoteEvaluator 音符评估器 (音准+节奏双维度评分)
- [x] MidiService MIDI 服务框架 (Stream 广播)
- [x] API Client (Dio + Token 管理)
- [x] Auth Repository (register/login/logout/token 持久化)
- [x] Score Repository (列表/搜索/详情/下载/收藏)
- [x] Practice Repository (start→note→end 完整流程封装)
- [x] SplashPage (登录状态检查, 自动路由)

**前端页面**
- [x] AuthPage — 登录/注册 (表单验证, 模式切换, 跳过登录)
- [x] HomePage — 设备连接卡片/快速开始/底部导航
- [x] ScoreLibraryPage — 乐谱库浏览 (分类/搜索/筛选)
- [x] ScoreViewPage — 乐谱详情 + OSMD 渲染集成 + 收藏
- [x] PracticePage — 练习界面 (实时统计/控制面板/报告弹窗)
- [x] PracticeHistoryPage — 练习历史 (分页/下拉刷新/左滑删除/详情)
- [x] StatisticsPage — 学习统计 (累计时长/等级分布/最佳成绩)
- [x] DeviceListPage — MIDI 设备扫描连接
- [x] ProfilePage — 个人页面 (用户信息/统计/菜单/登出)

### ⏳ 进行中
- [ ] 蓝牙 MIDI 底层实现 (flutter_midi_command 真机调试)
- [ ] USB MIDI 支持 (usb_serial + OTG 热插拔)
- [ ] ScoreFollower 和弦支持

### 📋 待开发
- [ ] 离线乐谱缓存
- [ ] 端到端测试
- [ ] App 发布 (Google Play / App Store)

---

## 文档

- [PRD — 产品需求文档](docs/PRD.md)
- [ARCHITECTURE — 技术架构](docs/ARCHITECTURE.md)
- [ROADMAP — 开发路线图](docs/ROADMAP.md)
- [SETUP — 环境配置](docs/SETUP.md)

---

*项目启动: 2026-03-15 | 最近更新: 2026-03-20 19:52*
