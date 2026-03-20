# DeepMusic - 开发路线图

> 版本: 1.1 | 更新: 2026-03-20

---

## Phase 1: MVP — 钢琴学习 App

### 总体时间线

```
2026-03                        2026-04                        2026-05
|── 基础设施 ──|── 核心功能 ──|── 集成测试 ──|── 发布准备 ──|
  Week 1-3       Week 4-6       Week 7-8       Week 9-10
```

> **说明**: 截至 2026-03-20，后端 API 已全部完成，移动端核心模块已完成（OSMD 集成、ScoreFollower 和弦、USB/BLE 双连接），仅差真机验证和个人资料编辑。

---

### 阶段 1: 数据管道 (Week 1-2)

**目标**: 打通乐谱从存储到渲染的完整链路

#### Week 1: MusicXML 解析器 ✅

- [x] 实现 `musicxml_parser.dart` (XML → Score 对象)
  - [x] 解析 `<score-partwise>` 结构
  - [x] 提取元数据（标题、作曲家、调号、拍号、tempo）
  - [x] 解析 `<note>` 元素（pitch、duration、rest、chord）
  - [x] 计算每个音符的 `startMs` 时间轴
  - [x] 处理 `<backup>` 和 `<forward>` 元素
- [x] 支持 score-timewise + 变拍号（覆盖典型 MusicXML 特性）
- [ ] 编写单元测试

#### Week 2: 乐谱渲染 ✅

- [x] 集成 OSMD (OpenSheetMusicDisplay) 到 WebView
  - [x] 创建 HTML 模板（内嵌 OSMD JS）
  - [x] 实现 JavaScript ↔ Flutter 通信桥
  - [x] 实现 `render(xml)` 方法
  - [x] 实现 `highlight(measureIndex)` 方法
  - [x] 实现 `scrollTo(position)` 方法
- [x] ScoreViewPage UI 完善
- [x] 练习页集成 OSMD 渲染 + 高亮跟随

**产出**: 能看到完整五线谱渲染，能高亮指定小节

---

### 阶段 2: MIDI 连接 (Week 3)

**目标**: 真实蓝牙 MIDI 设备连接可用

- [ ] `MidiService` 集成 `flutter_midi_command` 底层实现
  - [x] Android BLE 扫描 + 权限处理
  - [x] 连接 Yamaha P125 (代码)
  - [x] MIDI 事件接收与转换
  - [x] 断线检测与重连（指数退避 2s→4s→8s，最多 3 次）
- [x] USB OTG 底层: UsbSerial 枚举/连接/协议解析/热插拔检测
- [x] DeviceListPage UI: USB/BLE 分组展示
- [ ] 真机端到端测试

**产出**: 手机能通过蓝牙连接 P125，实时收到 MIDI 音符事件

---

### 阶段 3: 练习核心 (Week 4-5)

**目标**: 乐谱跟随 + 练习评估全流程打通

#### Week 4: Score Follower ✅

- [x] 改进 `ScoreFollower` 算法
  - [x] 实现容错机制（look-ahead window=3, max consecutive errors=5）
  - [x] 实现和弦匹配（ChordGroup + 300ms 时间窗口 + 匹配率评估）
  - [x] 实现跳过逻辑（容错跳过标记遗漏）
  - [x] 实现翻页信号 + 手动翻页手势 (横滑)
- [x] PracticePage UI 完善
  - [x] 实时音符显示 + 和弦指示栏
  - [x] 进度条
  - [x] 当前位置高亮（与 OSMD 集成）
  - [x] 翻页信号 + 页码指示器
- [x] 练习控制（开始/暂停/结束）

#### Week 5: Note Evaluator + 练习记录 ✅

- [x] `NoteEvaluator` 完善
  - [x] 音准评估
  - [x] 节奏评估
  - [x] 报告生成（PracticeReport）
- [ ] `PracticeSession` 管理器
  - [x] 练习开始/结束
  - [x] 评估数据收集
  - [x] 本地持久化（Hive）
- [x] PracticeResultPage（练习结果展示）
  - [x] 评分显示
  - [x] 正确率统计
  - [x] 错误音符列表

**产出**: 能完整练习一首曲谱，看到评分报告

---

### 阶段 4: 后端练习 API (Week 6)

**目标**: 练习记录后端 API 实现

- [ ] 实现 `practice.service.ts`
  - [x] `createSession(userId, scoreId)` → PracticeRecord
  - [x] `endSession(id, report)` → 更新记录 + 用户统计
  - [x] `getHistory(userId, page, limit)` → 分页列表
  - [x] `getStats(userId, period)` → 统计数据
- [x] 实现 `practice.ts` 路由（7 个端点 + 会话持久化）
- [x] 请求验证（express-validator）
- [ ] API 集成测试
- [x] Flutter API 客户端对接 (PracticeRepository)

**产出**: 练习记录能同步到服务端，历史记录可查询

---

### 阶段 5: 用户体验完善 (Week 7-8)

**目标**: 补全用户功能，打磨体验

- [ ] 用户注册/登录 UI
- [ ] 个人资料页面
- [ ] 练习历史列表 + 统计图表
- [ ] 收藏功能（本地 + 服务端同步）
- [ ] 乐谱分类筛选 UI
- [ ] 搜索功能 UI
- [ ] 暗色模式
- [ ] 横屏/竖屏适配
- [ ] 离线模式（内置乐谱可离线使用）
- [ ] 错误处理和空状态优化

---

### 阶段 6: 测试与发布 (Week 9-10)

**目标**: 质量保障，准备发布

- [ ] 核心功能端到端测试
- [ ] 性能优化
  - [ ] MIDI 事件延迟优化（目标 < 100ms）
  - [ ] 乐谱渲染首次加载优化（目标 < 2s）
  - [ ] 内存使用优化
- [ ] Android APK 构建测试
- [ ] iOS 构建测试（如 Mac 可用）
- [ ] App 图标 + 启动页
- [ ] 隐私政策 + 用户协议
- [ ] Bug 修复与回归测试
- [ ] Google Play 提交
- [ ] App Store 提交（如条件允许）

---

## Phase 2: 功能扩展 (2026-Q2)

| 功能 | 优先级 | 说明 |
|------|--------|------|
| 完整乐谱库 (100+) | 高 | 扩充曲谱覆盖 |
| AI 转谱 | 高 | 音频 → MusicXML |
| 音频调优 | 中 | 噪音消除 + 音色美化 |
| HarmonyOS 支持 | 中 | 适配鸿蒙系统 |
| 多乐器支持 | 低 | 吉他、小提琴等 |
| 弹奏搜索 | 中 | 演奏旋律搜索曲谱 |

---

## Phase 3: AI 增强 (2026-Q3)

| 功能 | 说明 |
|------|------|
| 大模型集成 | 音乐理解模型接入 |
| 智能评估 | 评估力度控制、情感表达 |
| 个性化推荐 | 基于练习数据的智能推荐 |
| AI 大师课 | 世界级演奏录音同步到乐谱 |

---

## 里程碑

| 里程碑 | 目标日期 | 依赖 | 状态 |
|--------|----------|------|------|
| M1: 乐谱渲染可用 | W2 末 | MusicXML 解析器 | ✅ 已完成 |
| M2: MIDI 连接可用 | W3 末 | 蓝牙调试环境 | ⏳ 代码完成，待真机 |
| M3: 完整练习流程 | W5 末 | M1 + M2 | ⏳ 代码完成，待真机 |
| M4: 后端 API 完整 | W6 末 | 练习数据模型 | ✅ 已完成 |
| M5: 用户功能完整 | W8 末 | M3 + M4 | ⏳ 75% (缺个人资料编辑) |
| M6: MVP 发布 | W10 末 | M5 + 测试 | 🔲 待开始 |

---

## 关键依赖关系

```
MusicXML Parser ──→ Score Renderer ──→ Score Follower ──→ Practice UI
                                          ↑
BLE MIDI Connection ─────────────────────┘

Note Evaluator ──→ Practice Result Page
     ↓
Practice Session ──→ Backend Practice API
```

> **关键路径**: MusicXML Parser → Score Renderer → Score Follower。任何一环阻塞，后续全部受影响。

---

## 风险与缓解

| 风险 | 影响 | 概率 | 缓解措施 |
|------|------|------|----------|
| iOS 开发需 Mac | 高 | 高 | 使用 Codemagic 云构建；先聚焦 Android |
| 蓝牙 MIDI 兼容 | 中 | 中 | 先专注 P125；封装适配层隔离差异 |
| MusicXML 格式复杂 | 中 | 中 | 分阶段支持：先处理常见元素，特殊情况降级 |
| OSMD 渲染性能 | 低 | 低 | 预渲染 + 缓存；Phase 2 考虑自定义渲染 |
| 曲谱资源不足 | 中 | 中 | 优先保证 10 首核心曲谱可用 |
| 全 AI 开发效率 | 中 | 高 | 文档先行，每阶段产出可验证 |

---

*路线图负责人: 项目团队 | 更新: 2026-03-20 20:24*
