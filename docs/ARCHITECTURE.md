# DeepMusic - Technical Architecture

## System Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        DeepMusic System                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐           │
│  │   iOS App    │  │ Android App  │  │  Web Admin   │           │
│  │   (Flutter)  │  │  (Flutter)   │  │  (Flutter)   │           │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘           │
│         │                 │                 │                    │
│         └─────────────────┼─────────────────┘                    │
│                           │                                      │
│                    ┌──────▼───────┐                              │
│                    │  API Gateway │                              │
│                    └──────┬───────┘                              │
│                           │                                      │
│         ┌─────────────────┼─────────────────┐                    │
│         │                 │                 │                    │
│  ┌──────▼──────┐  ┌──────▼──────┐  ┌──────▼──────┐              │
│  │ User Service│  │Score Service│  │Practice Svc │              │
│  └─────────────┘  └─────────────┘  └─────────────┘              │
│                                                                  │
│         ┌─────────────────┬─────────────────┐                    │
│         │                 │                 │                    │
│  ┌──────▼──────┐  ┌──────▼──────┐  ┌──────▼──────┐              │
│  │  PostgreSQL │  │   Redis     │  │ Cloud Storage│              │
│  │  Database   │  │   Cache     │  │  (Scores)    │              │
│  └─────────────┘  └─────────────┘  └─────────────┘              │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘

                    ┌──────────────┐
                    │ Yamaha P125  │
                    │ (MIDI BT)    │
                    └──────┬───────┘
                           │
                    Bluetooth MIDI
                           │
              ┌────────────┼────────────┐
              │            │            │
       ┌──────▼───┐ ┌──────▼───┐ ┌──────▼───┐
       │   iOS    │ │ Android  │ │   Web    │
       │   App    │ │   App    │ │  Admin   │
       └──────────┘ └──────────┘ └──────────┘
```

---

## Mobile App Architecture (Flutter)

### Project Structure

```
mobile/
├── lib/
│   ├── main.dart
│   ├── app.dart
│   │
│   ├── core/                    # 核心模块
│   │   ├── constants/
│   │   │   ├── app_colors.dart
│   │   │   ├── app_strings.dart
│   │   │   └── app_assets.dart
│   │   ├── theme/
│   │   │   ├── app_theme.dart
│   │   │   └── text_styles.dart
│   │   ├── router/
│   │   │   └── app_router.dart
│   │   └── utils/
│   │       ├── midi_utils.dart
│   │       └── score_utils.dart
│   │
│   ├── features/                # 功能模块
│   │   ├── home/
│   │   │   ├── pages/
│   │   │   ├── widgets/
│   │   │   └── providers/
│   │   │
│   │   ├── midi/               # MIDI 连接
│   │   │   ├── pages/
│   │   │   │   └── device_list_page.dart
│   │   │   ├── providers/
│   │   │   │   └── midi_provider.dart
│   │   │   └── services/
│   │   │       └── midi_service.dart
│   │   │
│   │   ├── score/              # 乐谱模块
│   │   │   ├── pages/
│   │   │   │   ├── score_library_page.dart
│   │   │   │   └── score_view_page.dart
│   │   │   ├── widgets/
│   │   │   │   ├── score_renderer.dart
│   │   │   │   └── score_follow_highlight.dart
│   │   │   ├── providers/
│   │   │   │   └── score_provider.dart
│   │   │   └── models/
│   │   │       ├── score.dart
│   │   │       └── note_event.dart
│   │   │
│   │   ├── practice/           # 练习模块
│   │   │   ├── pages/
│   │   │   │   ├── practice_page.dart
│   │   │   │   └── practice_result_page.dart
│   │   │   ├── widgets/
│   │   │   │   ├── note_indicator.dart
│   │   │   │   └── practice_controls.dart
│   │   │   ├── providers/
│   │   │   │   └── practice_provider.dart
│   │   │   └── services/
│   │   │       ├── score_follower.dart      # 乐谱跟随
│   │   │       ├── note_evaluator.dart      # 音符评估
│   │   │       └── practice_recorder.dart   # 练习记录
│   │   │
│   │   └── profile/
│   │       ├── pages/
│   │       └── providers/
│   │
│   ├── shared/                  # 共享组件
│   │   ├── widgets/
│   │   │   ├── dm_button.dart
│   │   │   ├── dm_card.dart
│   │   │   └── dm_loading.dart
│   │   └── services/
│   │       ├── api_service.dart
│   │       └── storage_service.dart
│   │
│   └── data/                    # 数据层
│       ├── repositories/
│       │   ├── score_repository.dart
│       │   └── user_repository.dart
│       ├── datasources/
│       │   ├── remote/
│       │   │   └── api_client.dart
│       │   └── local/
│       │       ├── database.dart
│       │       └── cache.dart
│       └── models/
│           └── api_models.dart
│
├── assets/
│   ├── images/
│   ├── fonts/
│   └── scores/                  # 内置曲谱 (MusicXML)
│       ├── classical/
│       └── popular/
│
├── pubspec.yaml
└── test/
```

---

## Core Components

### 1. MIDI Service

```dart
// lib/features/midi/services/midi_service.dart

class MidiService {
  Stream<MidiEvent>? _midiStream;
  
  // 扫描设备
  Future<List<MidiDevice>> scanDevices();
  
  // 连接设备
  Future<bool> connect(MidiDevice device);
  
  // 断开连接
  Future<void> disconnect();
  
  // 监听 MIDI 事件
  Stream<MidiEvent> get midiStream;
  
  // 连接状态
  Stream<MidiConnectionState> get connectionState;
}
```

### 2. Score Follower

```dart
// lib/features/practice/services/score_follower.dart

class ScoreFollower {
  final Score score;
  int _currentNoteIndex = 0;
  int _currentMeasure = 0;
  
  // 处理 MIDI 事件
  void processMidiEvent(MidiEvent event);
  
  // 获取当前应该弹奏的音符
  Note get currentExpectedNote;
  
  // 获取当前小节
  int get currentMeasure;
  
  // 是否需要翻页
  bool get needsPageTurn;
  
  // 进度流
  Stream<PracticeProgress> get progressStream;
}
```

### 3. Note Evaluator

```dart
// lib/features/practice/services/note_evaluator.dart

class NoteEvaluator {
  // 评估音符
  NoteEvaluation evaluate({
    required Note expected,
    required Note played,
    required Duration timing,
  });
  
  // 生成练习报告
  PracticeReport generateReport(List<NoteEvaluation> evaluations);
}

class NoteEvaluation {
  final bool isCorrect;        // 音准
  final double timingAccuracy; // 节奏准确度 0-1
  final Duration deviation;    // 偏差时长
}

class PracticeReport {
  final int totalNotes;
  final int correctNotes;
  final double timingScore;
  final double pitchScore;
  final double overallScore;
}
```

---

## Data Models

### Score (MusicXML 解析后)

```dart
class Score {
  final String id;
  final String title;
  final String composer;
  final String difficulty;  // beginner, intermediate, advanced
  final List<Part> parts;
  final Duration duration;
  final String? coverImage;
  final String musicXmlPath;
}

class Part {
  final String name;
  final List<Measure> measures;
}

class Measure {
  final int number;
  final List<Note> notes;
  final TimeSignature timeSignature;
  final KeySignature keySignature;
}

class Note {
  final String pitch;      // C4, D#5, etc.
  final Duration duration;
  final Duration startTime;
  final int measureNumber;
  final int staffPosition; // 用于定位渲染位置
}
```

---

## Key Dependencies

### pubspec.yaml

```yaml
dependencies:
  flutter:
    sdk: flutter
  
  # State Management
  flutter_riverpod: ^2.4.0
  
  # MIDI
  flutter_midi_command: ^0.5.0
  
  # Network
  dio: ^5.4.0
  
  # Storage
  sqflite: ^2.3.0
  shared_preferences: ^2.2.0
  
  # MusicXML Parsing
  xml: ^6.5.0
  
  # UI
  flutter_svg: ^2.0.0
  cached_network_image: ^3.3.0
  
  # Utils
  path_provider: ^2.1.0
  permission_handler: ^11.0.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^3.0.0
```

---

## Score Rendering Strategy

### Phase 1: WebView + OpenSheetMusicDisplay

```
Flutter WebView
      │
      ▼
┌─────────────────┐
│      HTML       │
│  ┌───────────┐  │
│  │   OSMD    │  │
│  │ Renderer  │  │
│  └───────────┘  │
│                 │
│  JavaScript     │
│  Bridge         │
└────────┬────────┘
         │
         ▼
    Flutter Dart
    (Highlight Control)
```

### Phase 2: Custom Flutter Renderer (可选)

```
MusicXML → Parser → NotePositions → CustomPainter
```

---

## Backend Architecture (Web Admin)

```
server/
├── src/
│   ├── modules/
│   │   ├── user/           # 用户管理
│   │   ├── score/          # 乐谱服务
│   │   ├── practice/       # 练习记录
│   │   └── feedback/       # Bug 跟踪
│   │
│   ├── core/
│   │   ├── config/
│   │   ├── middleware/
│   │   └── utils/
│   │
│   └── app.ts
│
├── prisma/
│   └── schema.prisma
│
└── package.json
```

---

## API Endpoints

### Auth
- `POST /auth/register`
- `POST /auth/login`
- `POST /auth/logout`

### Scores
- `GET /scores` - 获取曲谱列表
- `GET /scores/:id` - 获取曲谱详情
- `GET /scores/:id/xml` - 下载 MusicXML
- `POST /scores/:id/favorite` - 收藏

### Practice
- `POST /practice/start` - 开始练习
- `POST /practice/:id/note` - 上传音符事件
- `POST /practice/:id/end` - 结束练习
- `GET /practice/history` - 练习历史

### User
- `GET /user/profile`
- `PUT /user/profile`
- `GET /user/favorites`
- `GET /user/statistics`

---

## Deployment

### Mobile Apps
- iOS: App Store Connect
- Android: Google Play Console

### Backend
- 推荐方案：
  - Vercel / Railway (快速部署)
  - 阿里云 / 腾讯云 (国内用户)

### Database
- PostgreSQL (主数据库)
- Redis (缓存)

### Storage
- 阿里云 OSS / 腾讯云 COS (曲谱文件)
