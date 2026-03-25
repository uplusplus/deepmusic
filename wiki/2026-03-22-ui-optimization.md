# 2026-03-22 界面布局优化

## 概述

本次优化聚焦于乐谱查看页的**播放控制栏**和**钢琴键盘**两个核心交互组件，解决信息过载、操作不便、音域受限等问题。

---

## 1. 播放控制栏重构

### 问题分析

原版 `ScoreViewPage._buildPlaybackBar()` 将所有控制元素塞进一行：

```
[播放/暂停] [停止] [重复] [重复状态] [小节信息/时间] [变速下拉]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[双手] [右手] [左手]  ← 手部模式切换（额外一行）
```

问题：
- 元素过多，视觉无重点
- 变速用 DropdownButton，操作需要两次点击
- 手部模式三按钮占一整行
- 竖屏和横屏共用同一个组件，260px 侧栏放不下

### 解决方案

**三层分离设计：**

| 层 | 高度 | 内容 | 设计要点 |
|---|---|---|---|
| 进度条 | 4px | 顶部贯穿 | 圆角裁剪，`LinearProgressIndicator` |
| 核心控制 | ~56px | 渐变圆形播放按钮 + 小节/时间 + 停止 | 视觉重心，最大点击区域 |
| 辅助控制 | ~34px | 重复 / 变速 / 手部模式 / 移调 | 紧凑胶囊按钮，点击循环切换 |

**新增组件：**

- `_PlayButton` — 渐变圆形按钮，44px，带阴影
- `_CompactToggle` — 胶囊切换按钮，点击循环切换值

**横屏专用版 `_buildLandscapePlaybackBar()`：**

- 进度条 + 播放控制一行 + 辅助控制一行
- 侧栏宽度 260px → 280px
- 所有按钮更紧凑，文字缩写

### 关键代码变化

**变速控制** — 从 DropdownButton 改为循环切换：
```dart
static const _speedSteps = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

void _cycleSpeed() {
  final idx = _speedSteps.indexOf(_playbackRate);
  final next = _speedSteps[(idx + 1) % _speedSteps.length];
  _changeRate(next);
}
```

**手部模式** — 同理循环切换：
```dart
void _cycleHandMode() {
  const modes = [HandMode.both, HandMode.rightOnly, HandMode.leftOnly];
  final idx = modes.indexOf(_handMode);
  final next = modes[(idx + 1) % modes.length];
  _changeHandMode(next);
}
```

---

## 2. 钢琴键盘触摸弹奏

### 问题分析

原版 `PianoKeyboard` 只监听外部 MIDI 事件来高亮按键，但不响应屏幕触摸。用户在没有 MIDI 设备时无法试听。

### 解决方案

在 `PianoKeyboard` 中添加：

1. **`AudioSynthService` 初始化** — `initState` 时加载 SF2 音色
2. **`Listener` 包裹键盘** — 捕获 `onPointerDown / onPointerUp / onPointerCancel`
3. **HitTest 坐标映射** — 触摸坐标 → MIDI note number，黑键优先
4. **多指支持** — `_touchPointers` Map 记录 pointerId → noteNumber

```dart
Listener(
  onPointerDown: (event) {
    final note = _hitTestKey(event.localPosition, startNote, count, wkWidth, bkWidth);
    if (note != null) {
      _touchPointers[event.pointer] = note;
      _handleNoteDown(note, velocity: 100);
    }
  },
  onPointerUp: (event) {
    final note = _touchPointers.remove(event.pointer);
    if (note != null) _handleNoteUp(note);
  },
  ...
)
```

**HitTest 策略：** 黑键在上层 → 先检查黑键区域 → 未命中再检查白键

---

## 3. 完整 88 键可滚动键盘

### 问题分析

原版键盘根据屏幕宽度动态决定显示几个八度（2-5个），白键宽度自适应。但：

- 只能看到固定音区（通常是高音区）
- 无法触及低音 (A0-B2) 或高音 (C7-C8)
- 切换音区需要依赖外部（expectedPitches / MIDI 设备）

### 解决方案

**完全重写为 CustomPainter 渲染 + SingleChildScrollView 滚动：**

```
|← 可滚动区域 (52 白键 × 38px = 1976px) →|
┌──┬─┬──┬──┬─┬──┬─┬──┬──┬─┬──┬─┬──┬──┬─┬──┬─┬──┬──┬─┬──┬─┬──┬── ...
│C │█│D │E │█│F │█│G │A │█│B │█│C │D │█│E │█│F │G │█│A │█│B │C │ ...
└──┴─┴──┴──┴─┴──┴─┴──┴──┴─┴──┴─┴──┴──┴─┴──┴─┴──┴──┴─┴──┴─┴──┴── ...
```

**关键参数：**
- 音域范围：MIDI 21 (A0) → MIDI 108 (C8)
- 白键宽度：固定 38px
- 黑键宽度：38 × 0.58 ≈ 22px
- 白键总数：52 个 (A0..C8)
- 总宽度：52 × 38 = 1976px

**核心变化：**

| 项目 | 旧版 | 新版 |
|---|---|---|
| 渲染方式 | Widget 树 (Row + Positioned) | `CustomPainter` |
| 键数 | 屏幕宽度决定 (14-35 键) | 固定 88 键 |
| 滚动 | ❌ | ✅ `SingleChildScrollView` horizontal |
| 自动跟随 | 固定 baseOctave | `_scrollToNote()` 动画滚动 |
| 白键宽度 | 自适应 | 固定 38px |

**CustomPainter 优势：**
- 直接 `Canvas` 绘制，避免 88 个 Widget 重建
- `shouldRepaint` 只在 `pressedNotes` / `expectedPitches` 变化时重绘
- `RRect` 圆角矩形 + `MaskFilter.blur` 发光效果，视觉更精致

**滚动跟随逻辑：**
```dart
void _scrollToNote(int note) {
  if (!_scrollCtrl.hasClients) return;
  final whiteIdx = _noteToWhiteIndex(note);
  final targetOffset = whiteIdx * keyWidth - (context.size?.width ?? 300) / 2 + keyWidth;
  _scrollCtrl.animateTo(targetOffset.clamp(0, maxScroll),
    duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
}
```

MIDI 设备按键和屏幕触摸都会触发自动滚动，确保当前音符始终可见。

**触摸坐标校正：**

因为键盘内容比屏幕宽，`Listener` 的 `localPosition` 是相对可见区域的，需要加上 `scrollOffset`：

```dart
final scrollOffset = _scrollCtrl.hasClients ? _scrollCtrl.offset : 0.0;
final contentPos = Offset(event.localPosition.dx + scrollOffset, event.localPosition.dy);
final note = _hitTestKey(contentPos);
```

---

## 文件变更清单

| 文件 | 变更类型 | 说明 |
|---|---|---|
| `mobile/lib/features/score/pages/score_view_page.dart` | 修改 | 播放栏三层分离 + 横屏紧凑版 + 新增 `_PlayButton` / `_CompactToggle` |
| `mobile/lib/features/practice/widgets/piano_keyboard.dart` | 重写 | 完整 88 键 CustomPainter + 横向滚动 + 触摸弹奏 |
| `mobile/lib/core/router/app_router.dart` | 修改 | 路由调整 |
| `README.md` | 更新 | 新增 UI 优化记录 |

---

## 测试验证

- [x] 竖屏播放栏三层布局正常显示
- [x] 横屏播放栏紧凑版无溢出
- [x] 变速按钮循环切换 0.5→0.75→1.0→1.25→1.5→2.0
- [x] 88 键键盘完整渲染，左右滑动流畅
- [x] 触摸白键发声正确（C4=MIDI 60, D4=62, ...）
- [x] 触摸黑键发声正确（C#4=MIDI 61, D#4=63, ...）
- [x] MIDI 设备按键自动滚动到对应音区
- [x] 多指同时按下多个键

---

*文档创建: 2026-03-22 19:26*
