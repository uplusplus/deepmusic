# DeepMusic – Your Music AI Assistant

> DeepMusic is redefining how humans learn music, create music, and perform music.

---

## 产品概述

DeepMusic 是 AI 驱动的音乐学习助手，Phase 1 聚焦**钢琴学习**。通过蓝牙 MIDI 数字钢琴连接，提供实时乐谱跟随、练习评估和智能曲谱库。

### 核心功能

- 🎹 **MIDI 连接** — 蓝牙 BLE + USB OTG 双连接方式，自动扫描，统一事件流
- 📖 **智能乐谱跟随** — 实时跟踪弹奏位置，自动翻页
- 🎯 **练习评估** — 音准 + 节奏多维评分（S/A/B/C/D/F）
- 🔁 **区间循环练习** — 选择任意小节区间，反复循环练习难点段落
- ▶️ **自动播放** — 乐谱库自动播放试听，支持变速控制
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
| MIDI | flutter_midi_command (BLE + USB) 统一事件分发 |
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

## 最新更新 (2026-03-22 03:13)

### 🔧 蓝牙 MIDI 连接修复 (2026-03-22)
- 修复 `flutter_midi_command` 的 `stopScanningForBluetoothDevices()` 清空设备列表导致连接失败的 bug
- 核心改动：扫描完成后不主动停止 BLE 扫描，保持设备列表有效直到连接成功/断开/退出
- `_connectBleDevice` 连接前不再重新扫描，直接从运行中的设备列表获取新鲜设备引用
- 添加连接超时机制（15s），超时给出明确提示
- 连接成功后才停止 BLE 扫描，失败则扫描继续运行便于重试
- `DeviceListPage` 添加防重复点击保护，连接中显示 loading 状态
- 失败时显示具体错误原因（而非笼统的"连接失败"）
- Home 页新增 MIDI 测试面板，连接成功后可实时验证音符接收
- `disconnect()` 和 `dispose()` 确保停止 BLE 扫描

### 📱 蓝牙 MIDI 扫描修复 (v2) (2026-03-21)
- 修复 `BlePermissions._getAndroidSdkInt()` 永远返回 31 的 bug，改用 Android 原生 MethodChannel (`Build.VERSION.SDK_INT`) 获取真实 SDK 版本
- Android 12-13 正确请求 `ACCESS_FINE_LOCATION`（BLE 扫描必需，Android 14+ 已移除此要求）
- BLE 扫描初始化流程优化：先调用 `startBluetoothCentral()` + `waitUntilBluetoothIsInitialized()` 再开始扫描
- BLE 扫描时间 5s → 8s（BLE 发现设备需要更长时间）
- `scanAllDevices()` 增加蓝牙开启状态检查，蓝牙关闭时给出提示
- 新增原生 MethodChannel `deepmusic/device_info` (MainActivity.kt)

### 🔧 服务端与开发环境
- 后端服务绑定 `0.0.0.0:3000`，局域网可访问；WSL 环境需配置 Windows 端口转发 (`netsh interface portproxy`)
- `start.sh` 中 `tsc --noEmit` 因脚本文件 (`generate-scores.ts`) 隐式 any 类型报错，不影响运行

### 🔧 依赖与构建更新
- 更新 Flutter 依赖锁文件 (pubspec.lock)
- 更新 Android Gradle 版本 (gradle-wrapper.properties)

### 🎵 乐谱库完善
- 完成 30 首乐谱 MusicXML 文件生成（含真实旋律音符数据）
- 覆盖古典、影视、民歌、流行、爵士等分类
- 10 首初级 / 13 首中级 / 7 首高级

### 🔧 OSMD 渲染修复
- 将 OpenSheetMusicDisplay 库内联到 HTML（1.2MB），解决国内 CDN 加载失败问题
- 乐谱渲染器不再依赖外部网络，支持离线渲染

### 🗄️ 本地开发优化
- SQLite 数据库支持，无需 PostgreSQL 即可本地开发
- 乐谱生成脚本 `server/src/scripts/generate-scores.ts`
- 服务端 26 个 API 端点全部正常运行

### 📱 App 修复 (2026-03-21)
- 修复「自由练习」按钮点击无响应，跳转至乐谱库选曲
- 修复蓝牙 MIDI 扫描无设备问题
  - 添加 Android 12+ 运行时蓝牙权限请求（BLUETOOTH_SCAN / BLUETOOTH_CONNECT）
  - 修复设备类型过滤逻辑，不再错误过滤 BLE 设备
  - BLE 扫描时间 3s → 5s
- Manifest 添加 `usesCleartextTraffic` 支持 HTTP 后端连接
- 强化自动登录逻辑，token 有效直接进主页，过期才跳登录页

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
- [x] 练习会话持久化 (Prisma PracticeSession, 事务化操作, 替代内存 Map)
- [x] Prisma 数据模型 (Score/User/PracticeRecord/PracticeSession/Tag/Device) + 迁移
- [x] 30 首乐谱种子数据导入 + MusicXML 文件生成

**移动端核心模块**
- [x] Flutter 项目结构 + feature-based 组织
- [x] AutoPlayer 自动播放引擎 (MIDI 事件调度 + 变速 + OSMD 跟随)
- [x] Riverpod 状态管理 + 路由配置
- [x] Dart 数据模型 (Score/Part/Measure/Note/TimeSignature/KeySignature)
- [x] MusicXML 解析器 (score-partwise + timewise，含 divisions/和弦/休止符/变拍号)
- [x] OSMD 乐谱渲染器 (WebView + JS Bridge 双向通信)
- [x] ScoreFollower 乐谱跟随引擎 (和弦组匹配/容错跳过/自动翻页/手动翻页/区间循环)
- [x] NoteEvaluator 音符评估器 (音准+节奏双维度评分)
- [x] MidiService MIDI 服务 (BLE + USB 双连接, USB OTG 底层, BLE 断线自动重连)
- [x] API Client (Dio + Token 管理)
- [x] Auth Repository (register/login/logout/token 持久化)
- [x] Score Repository (列表/搜索/详情/下载/收藏)
- [x] Practice Repository (start→note→end 完整流程封装)
- [x] SplashPage (登录状态检查, 自动路由)

**前端页面**
- [x] AuthPage — 登录/注册 (表单验证, 模式切换, 跳过登录)
- [x] HomePage — 设备连接卡片/快速开始/底部导航
- [x] ScoreLibraryPage — 乐谱库浏览 (分类/搜索/筛选)
- [x] ScoreViewPage — 乐谱详情 + OSMD 渲染 + 自动播放试听 (变速 0.5x-2.0x) + 收藏
- [x] PracticePage — 练习界面 (OSMD 渲染 + 高亮跟随 + 手动翻页 + 区间循环练习 + 和弦显示/报告)
- [x] PracticeHistoryPage — 练习历史 (分页/下拉刷新/左滑删除/详情)
- [x] StatisticsPage — 学习统计 (累计时长/等级分布/最佳成绩)
- [x] DeviceListPage — MIDI 设备扫描连接 (USB/BLE 分组展示, 热插拔检测)
- [x] ProfilePage — 个人页面 (用户信息/统计/菜单/登出)

### ⏳ 进行中
- [x] 蓝牙 MIDI 连接 (BLE 连接已验证通过，真机测试通过 ✅)
- [ ] USB MIDI 真机调试
- [ ] 端到端集成测试
- [ ] 个人资料编辑 (F7.2)

### 📋 待开发
- [ ] 离线乐谱缓存 (Hive 本地存储)
- [x] 横屏/竖屏适配 (Practice/ScoreView/ScoreLibrary/Home 自适应布局)
- [ ] 暗色模式
- [ ] ScoreFollower 力度/表情评估 (Phase 2)
- [ ] App 发布 (Google Play / App Store)

---

## 文档

- [PRD — 产品需求文档](docs/PRD.md)
- [ARCHITECTURE — 技术架构](docs/ARCHITECTURE.md)
- [ROADMAP — 开发路线图](docs/ROADMAP.md)
- [SETUP — 环境配置](docs/SETUP.md)

---

*项目启动: 2026-03-15 | 最近更新: 2026-03-22 03:13*
