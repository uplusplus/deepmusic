# DeepMusic - 技术架构文档

> 版本: 1.1 | 更新: 2026-03-20

---

## 1. 系统总览

```
┌──────────────────────────────────────────────────────────────────┐
│                        DeepMusic System                          │
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐           │
│  │   iOS App    │  │ Android App  │  │  Web Admin   │           │
│  │   (Flutter)  │  │  (Flutter)   │  │  (Future)    │           │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘           │
│         │                 │                 │                    │
│         └─────────────────┼─────────────────┘                    │
│                           │ HTTPS                                │
│                    ┌──────▼───────┐                              │
│                    │  API Gateway │                              │
│                    │ (Rate Limit) │                              │
│                    └──────┬───────┘                              │
│                           │                                      │
│         ┌─────────────────┼─────────────────┐                    │
│         │                 │                 │                    │
│  ┌──────▼──────┐  ┌──────▼──────┐  ┌──────▼──────┐              │
│  │ Auth Routes │  │Score Routes │  │Practice Rt. │              │
│  └─────────────┘  └─────────────┘  └─────────────┘              │
│                                                                  │
│         ┌─────────────────┬─────────────────┐                    │
│         │                 │                 │                    │
│  ┌──────▼──────┐  ┌──────▼──────┐  ┌──────▼──────┐              │
│  │  PostgreSQL │  │   Redis     │  │  File Store  │              │
│  │  (Prisma)   │  │   Cache     │  │  (Scores)    │              │
│  └─────────────┘  └─────────────┘  └─────────────┘              │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘

                    ┌──────────────┐
                    │ Yamaha P125  │
                    │ (BLE + USB)  │
                    └──┬───────┬───┘
                       │       │
              BLE MIDI │       │ USB OTG MIDI
                       │       │
              ┌────────┼───┐   │
              │        │   │   │
       ┌──────▼───┐ ┌──▼───▼───┴───┐
       │   iOS    │ │   Android    │
       │  (BLE)   │ │ (BLE + USB)  │
       └──────────┘ └──────────────┘
                       │
              浏览器访问后端 API ─┘
```

---

## 2. 移动端架构 (Flutter)

### 2.1 项目结构

```
mobile/
├── lib/
│   ├── main.dart
│   ├── app.dart
│   │
│   ├── core/                         # 核心基础设施
│   │   ├── constants/
│   │   │   ├── app_colors.dart
│   │   │   ├── app_strings.dart
│   │   │   └── app_assets.dart
│   │   ├── theme/
│   │   │   └── app_theme.dart
│   │   ├── router/
│   │   │   └── app_router.dart
│   │   └── utils/
│   │       ├── midi_utils.dart
│   │       └── score_utils.dart
│   │
│   ├── features/                     # 功能模块 (Feature-based)
│   │   ├── home/
│   │   │   ├── pages/home_page.dart
│   │   │   ├── widgets/
│   │   │   └── providers/
│   │   │
│   │   ├── midi/                     # MIDI 连接模块
│   │   │   ├── pages/device_list_page.dart
│   │   │   ├── providers/midi_provider.dart
│   │   │   └── services/midi_service.dart
│   │   │
│   │   ├── score/                    # 乐谱模块
│   │   │   ├── pages/
│   │   │   │   ├── score_library_page.dart
│   │   │   │   └── score_view_page.dart
│   │   │   ├── widgets/
│   │   │   │   ├── score_renderer.dart       # WebView + OSMD 渲染
│   │   │   │   └── score_follow_highlight.dart
│   │   │   ├── providers/score_provider.dart
│   │   │   ├── models/score.dart
│   │   │   └── services/
│   │   │       ├── musicxml_parser.dart      # MusicXML 解析器
│   │   │       └── score_downloader.dart     # 乐谱下载/缓存
│   │   │
│   │   ├── practice/                 # 练习模块 (核心)
│   │   │   ├── pages/
│   │   │   │   ├── practice_page.dart
│   │   │   │   └── practice_result_page.dart
│   │   │   ├── widgets/
│   │   │   │   ├── note_indicator.dart
│   │   │   │   └── practice_controls.dart
│   │   │   ├── providers/practice_provider.dart
│   │   │   └── services/
│   │   │       ├── score_follower.dart       # 乐谱跟随引擎
│   │   │       ├── note_evaluator.dart       # 音符评估器
│   │   │       └── practice_session.dart     # 练习会话管理
│   │   │
│   │   └── profile/
│   │       ├── pages/profile_page.dart
│   │       └── providers/
│   │
│   ├── shared/                       # 共享组件
│   │   ├── widgets/
│   │   └── services/api_client.dart
│   │
│   └── data/                         # 数据层
│       ├── repositories/
│       ├── datasources/
│       └── models/
│
├── assets/
│   ├── images/
│   ├── fonts/
│   └── scores/                       # 内置 MusicXML 曲谱
│       ├── beginner/
│       ├── intermediate/
│       └── popular/
│
├── pubspec.yaml
└── test/
```

### 2.2 核心模块设计

#### 2.2.1 MIDI Service (蓝牙 + USB)

职责：管理 MIDI 设备的扫描、连接和事件分发。支持**蓝牙 BLE** 和 **USB OTG** 两种连接方式。

```dart
/// 连接方式
enum MidiConnectionType { bluetooth, usb }

class MidiService {
  // 单例模式
  static final MidiService _instance = MidiService._internal();
  factory MidiService() => _instance;

  // 流式 API
  Stream<MidiConnectionState> get connectionState;
  Stream<MidiEvent> get midiStream;
  Stream<List<MidiDevice>> get devices;

  // 当前连接方式
  MidiConnectionType? get connectionType;

  // 蓝牙操作
  Future<List<MidiDevice>> scanBleDevices();
  Future<bool> connectBle(MidiDevice device);
  Future<void> disconnectBle();

  // USB 操作
  Future<List<MidiDevice>> getUsbDevices();
  Future<bool> connectUsb(MidiDevice device);
  Future<void> disconnectUsb();

  // 通用
  Future<void> disconnect();  // 断开当前连接
}
```

**MidiEvent 数据结构**:
```dart
class MidiEvent {
  final MidiEventType type;  // noteOn, noteOff, controlChange
  final int note;            // MIDI 音符号 (0-127)
  final int velocity;        // 力度 (0-127)
  final int channel;         // 通道 (0-15)
  final DateTime timestamp;
  final MidiConnectionType source;  // bluetooth | usb
}
```

**蓝牙 BLE MIDI 实现要点**:
- 使用 `flutter_midi_command` 包封装
- Android 需要 `BLUETOOTH_CONNECT` + `BLUETOOTH_SCAN` 权限
- iOS 需要 `NSBluetoothAlwaysUsageDescription`
- 断线自动重连：最多 3 次，间隔 2 秒，指数退避
- 延迟目标: < 50ms

**USB MIDI 实现要点**:
- 使用 `usb_serial` 或 `flutter_libserialport` 包
- Android 需要 USB Host 权限 (`android.permission.USB_HOST`) + device_filter.xml
- iOS 不支持 USB MIDI（系统限制）
- 支持热插拔: 监听 USB 设备接入/拔出广播
- 延迟目标: < 20ms（显著优于蓝牙）

**连接策略**:
- USB 连接优先于蓝牙（延迟更低、更稳定）
- 当 USB 设备接入时，自动提示用户切换连接方式
- 两种连接共享统一的 `Stream<MidiEvent>` 分发，上层无需关心来源
- MIDI 事件通过 `StreamController.broadcast()` 分发，支持多个订阅者

#### 2.2.2 Score Follower (乐谱跟随引擎)

职责：实时跟踪用户弹奏位置，输出当前进度和翻页信号。

```dart
class ScoreFollower {
  final Score score;
  Stream<PracticeProgress> get progressStream;

  void processMidiEvent(NoteEvent event);
  Note? getCurrentExpectedNote();
  List<Note> getUpcomingNotes({int count = 5});
  void jumpToMeasure(int measureNumber);
  void reset();
}
```

**跟随算法设计 (Phase 1)**:

```
输入: NoteEvent (来自 MIDI)
输出: PracticeProgress (位置、进度、翻页信号)

核心逻辑:
1. 获取当前期望音符 expectedNote
2. 比较 event.noteNumber 与 expectedNote.pitchNumber
3. 匹配分支:
   a. 完全匹配 → 前进到下一个音符
   b. 不匹配 → 进入容错模式
4. 容错模式:
   - 等待 toleranceMs (默认 1500ms)
   - 期间如果用户弹出正确音符 → 回到正常模式
   - 超时仍未匹配 → 标记 expectedNote 为遗漏，跳过继续
5. 更新进度，检测翻页需求

和弦处理:
- 当下一个 expectedNote 是和弦（多个音符同一 startMs）时
- 收集同一时间窗口内（±300ms）的所有 NoteEvent
- 将集合与和弦音符集合对比
- 匹配率 > 50% 视为通过
```

**容错机制设计**:
```dart
class FollowerConfig {
  final int toleranceMs;         // 单音符容错等待时间 (默认 1500ms)
  final int chordWindowMs;       // 和弦时间窗口 (默认 300ms)
  final double chordMatchRatio;  // 和弦最低匹配率 (默认 0.5)
  final int maxSkips;            // 最大连续跳过数 (默认 3)
}
```

#### 2.2.3 Note Evaluator (音符评估器)

职责：对比期望音符和实际弹奏，生成评估结果。

```dart
class NoteEvaluator {
  NoteEvaluation evaluate({
    required Note expected,
    required NoteEvent played,
    required int expectedStartTimeMs,
    required int playedStartTimeMs,
  });

  PracticeReport generateReport({
    required String scoreId,
    required DateTime startTime,
    required DateTime endTime,
    required List<NoteEvaluation> evaluations,
  });
}
```

**评分算法**:
```
音准分 = (正确音符数 / 总音符数) × 100

节奏分:
  偏差 <= 200ms → 1.0
  偏差 <= 400ms → 0.8
  偏差 <= 600ms → 0.6
  偏差 > 600ms  → 0.4
  节奏分 = 所有音符节奏准确度的平均值 × 100

综合分 = 音准分 × 0.6 + 节奏分 × 0.4

等级: S(>=95) A(>=90) B(>=80) C(>=70) D(>=60) F(<60)
```

#### 2.2.4 MusicXML Parser (音乐 XML 解析器)

职责：将 MusicXML 文件解析为 Score 数据模型。

```
MusicXML File
    │
    ├── XML 解析 (package:xml)
    │     └── 提取 <score-partwise> 结构
    │
    ├── 元数据提取
    │     ├── title, composer, movement-title
    │     ├── key (fifths + mode)
    │     ├── time (beats + beat-type)
    │     └── divisions (每四分音符的 tick 数)
    │
    ├── 音符解析
    │     ├── pitch → Note (step + alter + octave → pitchNumber)
    │     ├── duration → Note.duration
    │     ├── type → Note.type (whole, half, quarter, eighth...)
    │     └── rest / chord 标记
    │
    ├── 时间轴计算
    │     └── 基于 divisions 和 tempo 生成每个音符的 startMs
    │
    └── 输出 Score 对象 (含所有 Part/Measure/Note)
```

**关键转换**:
```dart
// MusicXML pitch → MIDI pitchNumber
// step(C=0..6) + alter(-1/0/+1) + octave → (octave+1)*12 + noteIndex

// duration → 毫秒
// startMs = cumulativeDuration / divisions × (60000 / tempo)

// 示例: divisions=4, tempo=120
// 四分音符 duration=4 → 4/4 × 60000/120 = 500ms
```

#### 2.2.5 Score Renderer (乐谱渲染)

Phase 1 方案: **WebView + OpenSheetMusicDisplay (OSMD)**

```
┌─────────────────────────────┐
│       Flutter WebView       │
│  ┌───────────────────────┐  │
│  │     HTML + JS         │  │
│  │  ┌─────────────────┐  │  │
│  │  │      OSMD       │  │  │
│  │  │  (渲染 MusicXML) │  │  │
│  │  └─────────────────┘  │  │
│  │                       │  │
│  │  JavaScript Bridge    │  │
│  │  - render(xml)        │  │
│  │  - highlight(measure) │  │
│  │  - scrollTo(position) │  │
│  │  - getPositions()     │  │
│  └───────────┬───────────┘  │
│              │ JS Channel    │
└──────────────┼──────────────┘
               │
    Flutter Dart 控制层
    - score_renderer.dart
    - 高亮控制 / 翻页 / 缩放
```

**OSMD 集成要点**:
- HTML 模板内嵌 OSMD JS 库
- 通过 `webview_flutter` 的 JavaScript Channel 双向通信
- Flutter → JS: 发送 MusicXML 数据、高亮指令
- JS → Flutter: 返回音符位置坐标、渲染完成信号

### 2.3 关键依赖

```yaml
dependencies:
  flutter:
    sdk: flutter

  # 状态管理
  flutter_riverpod: ^2.4.0

  # MIDI (蓝牙 + USB)
  flutter_midi_command: ^0.5.2
  usb_serial: ^0.5.1

  # 网络
  dio: ^5.4.0
  retrofit: ^4.0.3

  # 本地存储
  hive_flutter: ^1.1.0

  # XML 解析
  xml: ^6.5.0

  # WebView (乐谱渲染)
  webview_flutter: ^4.4.2

  # UI
  flutter_svg: ^2.0.9
  cached_network_image: ^3.3.0

  # 工具
  uuid: ^4.2.1
  path_provider: ^2.1.1
  logger: ^2.0.2+1
```

---

## 3. 后端架构 (Express + TypeScript)

### 3.1 项目结构

```
server/
├── src/
│   ├── index.ts              # 入口，Express 应用配置
│   │
│   ├── routes/               # 路由层
│   │   ├── auth.ts           # POST /register, /login, /logout
│   │   ├── scores.ts         # CRUD + 搜索 + 上传
│   │   ├── practice.ts       # ⚠️ 待实现 - 练习记录 API
│   │   └── devices.ts        # 设备管理
│   │
│   ├── services/             # 业务逻辑层
│   │   ├── score.service.ts  # 乐谱业务逻辑
│   │   ├── auth.service.ts   # 认证逻辑 (待补充)
│   │   └── practice.service.ts # ⚠️ 待创建
│   │
│   ├── middleware/
│   │   ├── validate.ts       # 请求验证中间件
│   │   ├── error.ts          # 错误处理
│   │   └── notFound.ts       # 404 处理
│   │
│   ├── utils/
│   │   └── logger.ts         # Winston 日志
│   │
│   └── scripts/
│       ├── seed.ts           # 数据库初始化
│       └── import-scores.ts  # 乐谱数据导入
│
├── prisma/
│   ├── schema.prisma         # 数据模型
│   └── dev.db                # SQLite (开发)
│
├── .env.example
├── package.json
└── tsconfig.json
```

### 3.2 数据模型 (Prisma Schema)

```prisma
model Score {
  id              String    @id @default(uuid())
  title           String
  composer        String
  difficulty      String    @default("BEGINNER")  // BEGINNER | INTERMEDIATE | ADVANCED
  musicXmlPath    String
  fileSize        Int
  duration        Int       // 预估时长 (秒)
  measures        Int       // 小节数
  timeSignature   String    @default("4/4")
  keySignature    String    @default("C Major")
  tempo           Int       @default(120)  // BPM
  category        String?
  tags            Tag[]
  playCount       Int       @default(0)
  favoriteCount   Int       @default(0)
  status          String    @default("DRAFT")  // DRAFT | PUBLISHED | ARCHIVED
  isPublic        Boolean   @default(true)
  source          String?
  license         String?
  createdAt       DateTime  @default(now())
  updatedAt       DateTime  @updatedAt
  publishedAt     DateTime?
  practiceRecords PracticeRecord[]
  favorites       User[]    @relation("UserFavorites")
}

model User {
  id               String    @id @default(uuid())
  email            String    @unique
  password         String    // bcrypt hash
  nickname         String?
  avatar           String?
  totalPracticeTime Int      @default(0)
  totalSessions    Int       @default(0)
  totalNotes       Int       @default(0)
  practiceRecords  PracticeRecord[]
  favorites        Score[]   @relation("UserFavorites")
  createdAt        DateTime  @default(now())
  updatedAt        DateTime  @updatedAt
}

model PracticeRecord {
  id            String   @id @default(uuid())
  userId        String
  scoreId       String
  duration      Int      // 秒
  notesPlayed   Int
  pitchScore    Float    // 0-100
  rhythmScore   Float    // 0-100
  overallScore  Float    // 0-100
  grade         String   // S, A, B, C, D, F
  details       String?  // JSON: 完整评估数据
  startedAt     DateTime
  completedAt   DateTime @default(now())
  user          User     @relation(...)
  score         Score    @relation(...)
}

model Tag {
  id     String @id @default(uuid())
  name   String @unique
  scores Score[]
}
```

### 3.3 API Endpoints (已实现 + 待实现)

| 状态 | 方法 | 路径 | 说明 |
|------|------|------|------|
| ✅ | GET | `/health` | 健康检查 |
| ✅ | POST | `/api/auth/register` | 用户注册 |
| ✅ | POST | `/api/auth/login` | 用户登录 |
| ✅ | POST | `/api/auth/logout` | 用户登出 |
| ✅ | GET | `/api/scores` | 乐谱列表 (分页/筛选) |
| ✅ | GET | `/api/scores/recommended` | 推荐乐谱 |
| ✅ | GET | `/api/scores/search` | 搜索乐谱 |
| ✅ | GET | `/api/scores/:id` | 乐谱详情 |
| ✅ | POST | `/api/scores` | 上传乐谱 (MusicXML) |
| ✅ | PATCH | `/api/scores/:id` | 更新乐谱 |
| ✅ | POST | `/api/scores/:id/publish` | 发布乐谱 |
| ✅ | DELETE | `/api/scores/:id` | 删除乐谱 |
| ⚠️ | POST | `/api/practice/start` | 开始练习 - **TODO** |
| ⚠️ | POST | `/api/practice/:id/note` | 上传音符事件 - **TODO** |
| ⚠️ | POST | `/api/practice/:id/end` | 结束练习 - **TODO** |
| ⚠️ | GET | `/api/practice/history` | 练习历史 - **TODO** |
| ⚠️ | GET | `/api/practice/stats` | 统计数据 - **TODO** |
| ✅ | GET | `/api/devices` | 设备列表 |

### 3.4 中间件

- **Helmet**: 安全 HTTP 头
- **CORS**: 跨域配置（可配置 origin）
- **Rate Limiting**: `/api/` 路径 15 分钟 100 次
- **express-validator**: 请求参数校验
- **Winston**: 结构化日志
- **Multer**: 文件上传（限 10MB，仅 MusicXML 格式）

### 3.5 数据库策略

| 环境 | 数据库 | 说明 |
|------|--------|------|
| 开发 | SQLite | 轻量，`prisma/dev.db` |
| 生产 | PostgreSQL | 需在 `.env` 中配置 `DATABASE_URL` |
| 缓存 | Redis | 已引入 `ioredis` 依赖，待集成 |

**迁移路径**: Prisma 支持同一 schema 切换 provider，迁移文件从 SQLite → PostgreSQL 无需修改 schema，只需更换 `datasource.db`。

---

## 4. 音乐数据模型

### 4.1 乐谱数据模型 (Dart)

```dart
class Score {
  final String id;
  final String title;
  final String composer;
  final String difficulty;    // beginner | intermediate | advanced
  final List<Part> parts;     // 声部
  final int totalMeasures;
  final Duration estimatedDuration;
  final String musicXmlPath;
}

class Part {
  final String name;          // 如 "Piano", "P1"
  final List<Measure> measures;
}

class Measure {
  final int number;
  final List<Note> notes;
  final TimeSignature timeSignature;
  final KeySignature keySignature;
}

class Note {
  final String pitch;         // "C4", "D#5"
  final int pitchNumber;      // MIDI 音符号 (0-127)
  final double duration;      // 以四分音符为单位 (1.0 = 四分音符)
  final int startMs;          // 从曲首开始的毫秒数
  final int measureNumber;
}
```

### 4.2 MIDI 音符 ↔ 名称映射

```
MIDI pitchNumber = (octave + 1) × 12 + noteIndex

noteIndex: C=0, C#=1, D=2, D#=3, E=4, F=5, F#=6, G=7, G#=8, A=9, A#=10, B=11

示例: A4 (440Hz) → (4+1)×12 + 9 = 69
      C4 (中央C) → (4+1)×12 + 0 = 60
```

---



## 4.5 区间循环练习 (F8)

### 数据流

```
用户选择区间 [startMeasure, endMeasure]
    │
    └── ScoreFollower.setLoopRange(start, end)
          │
          ├── 计算区间对应的 _chordGroup 起止索引
          ├── 设置 _loopStartGroupIndex / _loopEndGroupIndex
          └── 标记 _loopEnabled = true

循环中:
    processMidiEvent()
        │
        ├── 正常匹配逻辑
        │
        └── _advanceToNextGroup()
              │
              └── if (_currentGroupIndex > _loopEndGroupIndex)
                    ├── _loopCycle++
                    ├── 生成本次循环评分 → LoopCycleScore
                    ├── _currentGroupIndex = _loopStartGroupIndex
                    └── _emitProgress() (含 loopCycle 字段)
```

### ScoreFollower 扩展

```dart
// 新增属性
int? _loopStartGroupIndex;
int? _loopEndGroupIndex;
bool _loopEnabled = false;
int _loopCycle = 0;
List<double> _loopCycleScores = [];

// 新增方法
void setLoopRange(int startMeasure, int endMeasure) {
  _loopStartGroupIndex = _findGroupIndexForMeasure(startMeasure);
  _loopEndGroupIndex = _findGroupIndexForMeasure(endMeasure);
  _loopEnabled = true;
  _loopCycle = 0;
  _loopCycleScores.clear();
}

void clearLoopRange() {
  _loopEnabled = false;
  _loopStartGroupIndex = null;
  _loopEndGroupIndex = null;
}

// 在 _advanceToNextGroup() 中追加:
if (_loopEnabled && _currentGroupIndex > _loopEndGroupIndex!) {
  _loopCycleScores.add(currentCycleScore);
  _loopCycle++;
  _currentGroupIndex = _loopStartGroupIndex!;
  // 重置循环内统计
}
```

### PracticeProgress 扩展

```dart
class PracticeProgress {
  // ... 原有字段
  final bool loopEnabled;
  final int loopCycle;
  final int? loopStartMeasure;
  final int? loopEndMeasure;
  final double? loopBestScore;
}
```

### OSMD 区间高亮

```javascript
// index.html 新增 JS 方法
function highlightLoopRange(startMeasure, endMeasure) {
  clearHighlight();
  const svg = document.querySelector('#score-container svg');
  for (let i = startMeasure; i <= endMeasure; i++) {
    if (i >= measurePositions.length) break;
    const pos = measurePositions[i];
    const rect = document.createElementNS('http://www.w3.org/2000/svg', 'rect');
    rect.setAttribute('class', 'loop-highlight');
    rect.setAttribute('x', pos.x);
    rect.setAttribute('y', pos.y - 10);
    rect.setAttribute('width', pos.width);
    rect.setAttribute('height', pos.height + 20);
    rect.setAttribute('fill', 'rgba(255, 193, 7, 0.15)');
    rect.setAttribute('stroke', 'rgba(255, 193, 7, 0.5)');
    rect.setAttribute('stroke-width', '2');
    rect.setAttribute('rx', '4');
    svg.insertBefore(rect, svg.firstChild);
  }
}
```

## 4.6 自动播放乐谱 (F9)

### AutoPlayer 类设计

```dart
class AutoPlayer {
  final Score score;
  final MidiService _midiService = MidiService();

  // 调度事件列表
  late List<ScheduledMidiEvent> _events;
  int _eventIndex = 0;

  // 播放状态
  bool _isPlaying = false;
  bool _isPaused = false;
  double _playbackRate = 1.0;
  int _startMeasure = 1;

  // 时间管理
  final Stopwatch _stopwatch = Stopwatch();
  Timer? _tickTimer;

  // 状态流
  final _stateController = StreamController<AutoPlayState>.broadcast();
  Stream<AutoPlayState> get stateStream => _stateController.stream;

  // 进度回调
  final _progressController = StreamController<int>.broadcast(); // currentMeasure
  Stream<int> get measureStream => _progressController.stream;
}

class ScheduledMidiEvent {
  final int noteNumber;
  final int velocity;
  final int absoluteMs;    // 从曲首开始的绝对毫秒数
  final bool isNoteOn;
  final int measureNumber;

  ScheduledMidiEvent({ ... });
}

class AutoPlayState {
  final bool isPlaying;
  final bool isPaused;
  final double progress;      // 0.0 - 1.0
  final int currentMeasure;
  final double playbackRate;
  final Duration position;
  final Duration duration;
}
```

### 播放调度逻辑

```dart
void play({int fromMeasure = 1, double rate = 1.0}) {
  _playbackRate = rate;
  _startMeasure = fromMeasure;

  // 从 Score.allNotes 生成调度事件
  _events = _buildScheduledEvents();
  _eventIndex = _findStartIndex(fromMeasure);

  _stopwatch.reset();
  _stopwatch.start();

  // 10ms tick 检查待发送事件
  _tickTimer = Timer.periodic(Duration(milliseconds: 10), (_) => _tick());
  _isPlaying = true;
}

void _tick() {
  if (!_isPlaying || _isPaused) return;

  final elapsedMs = _stopwatch.elapsedMilliseconds;
  final playbackMs = (elapsedMs * _playbackRate).round();

  // 批量发送同一时间点的事件 (和弦支持)
  while (_eventIndex < _events.length) {
    final event = _events[_eventIndex];
    final adjustedMs = (event.absoluteMs / _playbackRate).round();

    if (adjustedMs > playbackMs) break; // 还没到时间

    if (event.isNoteOn) {
      _midiService.sendNoteOn(event.noteNumber, event.velocity);
    } else {
      _midiService.sendNoteOff(event.noteNumber);
    }

    // 通知 UI 更新小节位置
    _progressController.add(event.measureNumber);
    _eventIndex++;
  }

  // 播放完毕
  if (_eventIndex >= _events.length) {
    stop();
  }
}

List<ScheduledMidiEvent> _buildScheduledEvents() {
  final events = <ScheduledMidiEvent>[];
  final notes = score.allNotes;
  final beatMs = 60000 / (score.bpm); // 假设有 bpm 属性

  for (final note in notes) {
    final durationMs = (note.duration * beatMs).round();
    // Note On
    events.add(ScheduledMidiEvent(
      noteNumber: note.pitchNumber,
      velocity: 80,
      absoluteMs: note.startMs,
      isNoteOn: true,
      measureNumber: note.measureNumber,
    ));
    // Note Off
    events.add(ScheduledMidiEvent(
      noteNumber: note.pitchNumber,
      velocity: 0,
      absoluteMs: note.startMs + durationMs,
      isNoteOn: false,
      measureNumber: note.measureNumber,
    ));
  }

  events.sort((a, b) => a.absoluteMs.compareTo(b.absoluteMs));
  return events;
}
```

### OSMD 播放跟随

```dart
// AutoPlayer.measureStream → PracticePage/ScoreViewPage
// 驱动 ScoreRenderer.highlightMeasure(currentMeasure)
```

## 5. 构建与部署

### 5.1 移动端

| 平台 | 构建方式 | 分发 |
|------|----------|------|
| Android | `flutter build apk` / `flutter build appbundle` | Google Play |
| iOS | `flutter build ios` (需 macOS) | App Store |

### 5.2 后端

```bash
# 开发
cd server && npm run dev

# 生产构建
npm run build  # tsc 编译
npm start      # node dist/index.js

# 数据库
npm run db:migrate  # prisma migrate dev
npm run db:seed     # 初始化种子数据
npm run scores:import  # 导入乐谱数据
```

### 5.3 部署方案

| 组件 | 推荐方案 | 备选 |
|------|----------|------|
| 后端 | Railway / Vercel | 阿里云 / 腾讯云 ECS |
| 数据库 | PostgreSQL (云托管) | 自建 |
| 文件存储 | 阿里云 OSS / 腾讯云 COS | 本地 + CDN |
| Redis | 云托管 Redis | 自建 |

---

## 6. 当前实现状态

| 模块 | 状态 | 说明 |
|------|------|------|
| Express 服务框架 | ✅ | 完整中间件链 |
| Auth 路由 | ✅ | 注册/登录/登出 |
| Score CRUD | ✅ | 完整 REST API |
| 文件上传 | ✅ | Multer + MusicXML 过滤 |
| Prisma Schema | ✅ | 5 个模型，关系完整 |
| 乐谱种子数据 | ✅ | 30 首已导入 |
| Practice 路由 | ✅ | 完整实现 + Prisma 事务 + 会话持久化 |
| MIDI Service (蓝牙) | ⚠️ | BLE 扫描/连接/数据接收完成，断线自动重连，待真机调试 |
| MIDI Service (USB) | ⚠️ | USB OTG 底层 UsbSerial 枚举/连接/协议解析，热插拔检测，待真机调试 |
| Score Follower | ✅ | 单音符 + 和弦组匹配，容错跳过，翻页信号，手动翻页 |
| Note Evaluator | ✅ | 音准+节奏双维度，报告生成 |
| MusicXML Parser | ✅ | score-partwise + timewise，变拍号，和弦/休止符/backup/forward |
| 乐谱渲染 (OSMD) | ✅ | WebView OSMD 集成，高亮控制，滚动，缩放，练习页集成 |
| 练习会话管理 | ✅ | Prisma PracticeSession 持久化，事务化操作 |
| 区间循环练习 (F8) | ❌ | ScoreFollower 循环模式 + OSMD 区间高亮 + 独立评分 |
| 自动播放 (F9) | ❌ | AutoPlayer MIDI 调度器 + 变速 + OSMD 跟随 |

---

*架构负责人: 项目团队 | 更新: 2026-03-20 20:29*
