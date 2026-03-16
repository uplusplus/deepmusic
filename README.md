# DeepMusic – Your Music AI Assistant

> DeepMusic is redefining how humans learn music, create music, and perform music.
> DeepMusic embodies the dual soul of a concert pianist and an elite AI engineer — a musical revolution written in code.

---

## Product Overview

DeepMusic is the world's first large-scale AI assistant that truly understands music.

Powered by a Music Large Model, trained on millions of audio recordings, sheet music, text, and visual data, DeepMusic goes beyond sound recognition.

**It understands musical intention.**

It doesn't just hear your notes — it understands your struggles, guides your progress, and practices with you like a personal music mentor.

---

## Platform Support

| Platform | Devices |
|----------|---------|
| iOS | iPhone, iPad |
| Android | Phones, Tablets |
| HarmonyOS | Phones, Tablets |

---

## Core Features

### 🎼 Intelligent Score Library | Search by Playing

- Tens of thousands of professionally curated scores
- Repertoire: Beyer, Czerny, Bach, Chopin to modern and pop
- **Play to Search**: Play the melody in your mind → identify within 3 seconds
- Instant score location from millions of sheets

### 📖 Intelligent Score Following | AI That Understands You

- First score-following system that understands **musical intention**, not just notes
- Wrong note? It knows what you meant
- Difficult passage? It stays with you
- Jump to climax? It follows instantly
- **AI Page Turning**: Auto-flip at the perfect moment

### 🎹 AI Practice Companion | Your 24/7 Music Teacher

- Real-time note recognition
- Gentle Real-time Error Correction
- Multi-dimensional AI Evaluation:
  - Pitch accuracy
  - Rhythmic stability
  - Dynamics control
  - Emotional expression
  - Performance completeness
- Distinguishes artistic rubato from instability

### 🎵 Music Transcription | Preserve Every Inspiration

- Improvise → Transcribe → Magic
- Output: Complete staff score with:
  - Precise notes
  - Tempo detection
  - Key analysis
  - Slurs & articulations
  - Subtle rubato captured
- Export to MusicXML

### 🎛️ AI Audio Tuning | One-Click Studio Sound

- Noise removal
- Pitch correction
- Steinway-grade tone
- Expanded dynamic range
- From practice room to concert hall — in one click

### 📤 Score Upload | Bring Old Scores to Life

- Upload any file: yellowed sheets, handwritten exercises, PDFs
- Convert to interactive digital scores
- Every musical memory is reborn

### 🎓 AI Masterclass | Play with Legends

- World-class performance recordings synced to sheet music
- Tap any bar → jump to corresponding audio
- Dialogue with masters

---

## Development Phases

### Phase 1: Cross-Platform Piano Learning App

**Goal**: MVP for piano learning with Bluetooth MIDI support

**Platforms**: iOS, Android, HarmonyOS

**Core Features**:
- Bluetooth MIDI connection to digital pianos
- Real-time note recognition
- Score following
- Basic practice evaluation
- Score library (curated subset)

**Timeline**: TBD

### Phase 2: Full Feature Rollout

- Complete score library
- AI transcription
- Audio tuning
- Play-to-search

### Phase 3: Multi-Instrument Support

- Guitar learning
- Other instruments

---

## Technical Requirements (Phase 1)

### Bluetooth MIDI
- iOS: Core MIDI / External Accessory Framework
- Android: Android MIDI API (API 23+)
- HarmonyOS: HarmonyOS MIDI API

### Cross-Platform Framework
- Options: Flutter / React Native / KMP (Kotlin Multiplatform)
- TBD based on discussion

### Audio Engine
- Real-time pitch detection
- Low-latency audio processing
- Options: FMOD / AudioKit / Custom DSP

### Sheet Music Rendering
- MusicXML parsing
- Interactive score display
- Options: OpenSheetMusicDisplay / VexFlow / Custom

---

## Project Structure

```
DeepMusic/
├── README.md
├── docs/
│   ├── PRD.md           # Product Requirements Document
│   ├── ARCHITECTURE.md  # Technical Architecture
│   └── ROADMAP.md       # Development Roadmap
├── design/
│   └── ui/              # UI/UX designs
├── src/
│   ├── mobile/          # Cross-platform mobile app
│   ├── core/            # Shared business logic
│   └── audio/           # Audio processing engine
└── assets/
    └── scores/          # Sample scores for testing
```

---

## Project Status

✅ **已完成:**
- [x] 需求讨论与决策记录
- [x] PRD 文档
- [x] 技术架构设计
- [x] 开发路线图
- [x] Flutter 项目创建与依赖安装
- [x] 核心模块代码框架
- [x] Web 后端 API 开发完成
- [x] 数据库初始化 (PostgreSQL + Redis)
- [x] 30 首无版权乐谱数据导入
- [x] 后端服务本地运行 (http://localhost:3000)
- [x] Flutter Web 构建成功
- [x] API 客户端配置完成
- [x] Android Studio 已安装 (D:\03_Android\android-studio)
- [x] Android SDK 已配置 (D:\03_Android\Sdk)
- [x] 真实 MusicXML 文件上传 (致爱丽丝.xml, 小步舞曲.xml, 小星星变奏曲.xml)

⏳ **进行中:**
- [ ] 配置 Android 开发环境
- [ ] 上传更多 MusicXML 文件

📋 **待办:**
- [ ] 配置 Flutter Android 开发环境
- [ ] 实现蓝牙 MIDI 连接 (Yamaha P125)
- [ ] 实现 MusicXML 解析与渲染 (OSMD)
- [ ] 实现乐谱跟随逻辑
- [ ] 实现音符评估算法
- [ ] 前后端联调测试
- [ ] 构建 Android APK

---

## Quick Start

```bash
# 安装 Flutter (如未安装)
# Windows: https://docs.flutter.dev/get-started/install/windows

# 进入移动端项目
cd DeepMusic/mobile

# 安装依赖
flutter pub get

# 运行应用
flutter run
```

---

## Documentation

- [PRD - 产品需求文档](docs/PRD.md)
- [ARCHITECTURE - 技术架构](docs/ARCHITECTURE.md)
- [ROADMAP - 开发路线图](docs/ROADMAP.md)
- [SETUP - 开发环境配置](docs/SETUP.md)

---

## Contact

*Project initiated: 2026-03-15*
