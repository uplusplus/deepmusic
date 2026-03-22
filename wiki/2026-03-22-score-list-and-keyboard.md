# 2026-03-22 乐谱列表 + 虚拟键盘优化

## 概述

本次优化聚焦于乐谱播放页面的三个核心体验：**乐谱切换便利性**、**虚拟键盘可用性**和**播放同步高亮**。

---

## 1. 乐谱列表侧栏

### 问题

播放页面只能查看当前乐谱，切换其他乐谱需要返回乐谱库重新选择，操作路径过长。

### 方案

- **竖屏**：AppBar 新增 🎵 按钮，点击弹出 `DraggableScrollableSheet` 底部抽屉（可拖拽高度 30%-85%）
- **横屏**：右侧控制面板中间插入嵌入式乐谱列表（替换原来的 Spacer）

### 关键改动

**`score_view_page.dart`**

- `widget.scoreId` → `_currentScoreId`（可变状态，支持动态切换）
- 新增 `_switchScore(ScoreModel)` — 停止播放 → 重置状态 → 刷新 provider → 重载 XML
- 新增 `_buildScoreListEmbedded()` — 横屏侧栏嵌入列表，AsyncValue 驱动
- 新增 `_showScoreListSheet()` — 竖屏底部抽屉，Consumer 实时获取列表
- 新增 `_buildScoreListItem()` — 统一列表项，当前乐谱高亮 + play_circle 图标

**数据流**
```
点击列表项 → _switchScore(item) → stop() + setState(currentScoreId) → 
invalidate(scoreDetailProvider) → _loadScoreXml() → rebuild
```

---

## 2. 虚拟键盘修复

### 问题

1. 播放页面点击虚拟键盘无响应
2. 键盘高度过小（竖屏 100px / 横屏 80px），对比练习页面 200px 差距明显

### 原因分析

键盘使用 `Expanded` 包裹，导致布局挤压异常。`Expanded` 分配剩余空间但可能使键盘容器高度与 `PianoKeyboard` 内部 `SingleChildScrollView` 的约束不一致。

### 修复

- `Expanded` → 固定高度 `SizedBox` 包裹 `PianoKeyboard`
- 竖屏：100 → 200（与练习页面对齐）
- 横屏：80 → 160

```dart
// 修复前
if (_playState.isPlaying && _showKeyboard)
  PianoKeyboard(expectedPitches: const {}, height: 100),

// 修复后
if (_playState.isPlaying && _showKeyboard)
  SizedBox(
    height: 200,
    child: PianoKeyboard(expectedPitches: const {}, playingNotes: _playingNotes, playingVersion: _playingVersion, height: 200),
  ),
```

---

## 3. 虚拟键盘播放同步高亮

### 需求

播放时虚拟键盘应实时高亮当前正在发音的音符，与乐谱播放同步。

### 方案

#### AutoPlayer 新增 noteStream

```dart
class PlayingNoteEvent {
  final int noteNumber;
  final bool isOn; // true=noteOn, false=noteOff
}

// 新增 noteController
final _noteController = StreamController<PlayingNoteEvent>.broadcast();
Stream<PlayingNoteEvent> get noteStream => _noteController.stream;
```

在 `_tick()` 中，每个音符 on/off 事件发射 `PlayingNoteEvent`。

#### PianoKeyboard 新增 playingNotes

```dart
final Set<int> playingNotes;
final int playingVersion; // 父级版本号，变化触发重绘
```

**颜色方案**（优先级从高到低）：
1. 用户按键 — 蓝色 (`AppColors.accent`)
2. 播放中 — 橙色 (`#FF9800` 发光 + `#E65100` 填充)
3. 应弹音符 — 浅蓝 (`AppColors.primaryLight`)
4. 普通 — 白/黑

#### shouldRepaint 版本号机制

**踩坑**：`_playingNotes` 就地修改（`add`/`remove`），Set 引用不变。集合比较 `containsAll` 无法可靠检测变化，导致 CustomPainter 不触发重绘。

**解决方案**：使用父级版本号 `_playingVersion`，每次修改 `_playingNotes` 时递增，传入 Painter 做整数比较。

```dart
// ScoreViewPage
setState(() {
  _playingNotes.add(event.noteNumber);
  _playingVersion++; // 关键：触发 shouldRepaint
});

// _PianoPainter.shouldRepaint
return old.playingVersion != playingVersion; // 整数比较，100% 可靠
```

### 文件改动

| 文件 | 改动 |
|------|------|
| `auto_player.dart` | 新增 `PlayingNoteEvent` 类 + `_noteController` + noteStream + tick 中发射事件 + dispose 关闭 |
| `piano_keyboard.dart` | 新增 `playingNotes`/`playingVersion` 参数 + 画笔绘制播放音符 (橙色高亮) + `shouldRepaint` 版本号比较 |
| `score_view_page.dart` | 新增 `_playingNotes`/`_playingVersion` + 订阅 noteStream + 传递给 PianoKeyboard + 停止/暂停时清空 |

---

## 4. 音符点击与循环练习

### 已实现（早前批次）

- OSMD HTML 添加音符位置收集 + SVG 点击监听
- `ScoreRenderer` 新增 `NoteInfo` + `onNoteTapped` 回调
- `ScoreViewPage` 重复模式 UI + 循环区间选择
- `AutoPlayer` 循环播放支持（`setLoopRange`/`clearLoop`/`toggleLoop`）
- 播放时音符跟随高亮（绿色半透明覆盖层）

---

## 经验教训

1. **CustomPainter shouldRepaint 不要依赖集合比较** — 就地修改的 Set 引用不变，`containsAll`/length 比较不可靠。用版本号或数据快照。
2. **Expanded vs SizedBox** — 键盘等交互组件用固定尺寸 `SizedBox` 更可靠，避免布局约束意外变化。
3. **didUpdateWidget 的陷阱** — 当父级传入的 Set 引用不变时，`didUpdateWidget` 中的 `!=` 比较永远 false。版本号从父级传入更可靠。
