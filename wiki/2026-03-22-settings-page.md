# 应用设置页 — 2026-03-22

## 概述

新增应用设置页，支持用户自定义音频输出方式和虚拟键盘默认显示行为。设置通过 SharedPreferences 持久化，全局生效。

## 功能

### 1. 音频输出模式

| 模式 | 说明 |
|------|------|
| **MIDI** | 音频通过连接的 MIDI 设备输出（电钢琴/合成器），本机不发声 |
| **本机** | 音频通过内置 SF2 合成器从手机/平板扬声器输出，不发送 MIDI |

**影响范围：**
- `AutoPlayer` 自动播放 → 根据设置决定 `sendNoteOn/Off`（MIDI）或 `noteOn/Off`（合成器）
- `PianoKeyboard` 虚拟键盘触摸弹奏 → 同上
- `pause()` / `stop()` / `dispose()` → 只清理对应输出通道的资源

### 2. 默认显示键盘

控制播放乐谱时是否默认展示虚拟钢琴键盘。

- **开**（默认）：进入乐谱播放时自动显示键盘
- **关**：默认隐藏键盘，可手动通过播放栏按钮切换

**影响范围：**
- `ScoreViewPage` 播放时竖屏/横屏布局中的 PianoKeyboard 显示逻辑
- 播放栏提供键盘切换按钮（🎹 图标），可临时覆盖默认设置

## 实现

### 新增文件

| 文件 | 说明 |
|------|------|
| `lib/features/settings/services/app_settings.dart` | 设置服务，单例模式，SharedPreferences 持久化 |
| `lib/features/settings/pages/settings_page.dart` | 设置页面 UI |

### 修改文件

| 文件 | 改动 |
|------|------|
| `lib/main.dart` | 启动时 `await AppSettings().load()` |
| `lib/core/router/app_router.dart` | 新增 `/settings` 路由 |
| `lib/features/profile/pages/profile_page.dart` | "设置"菜单项接入路由 |
| `lib/features/practice/services/auto_player.dart` | `_tick()` / `_allNotesOff()` / `play()` / `pause()` 读取音频输出设置 |
| `lib/features/practice/widgets/piano_keyboard.dart` | `_handleNoteDown()` / `_handleNoteUp()` / `dispose()` 读取音频输出设置 |
| `lib/features/score/pages/score_view_page.dart` | 播放时显示键盘（受设置控制）+ 播放栏键盘切换按钮 |

### 设置页 UI

- **音频输出**：SegmentedButton（MIDI / 本机）一键切换
- **默认显示键盘**：SwitchListTile 开关

入口：「我的」页 → 「设置」

## 数据流

```
用户操作 SettingsPage
  → AppSettings().setAudioOutputMode() / setShowKeyboardDefault()
  → SharedPreferences 持久化

AutoPlayer._tick()
  → 读取 AppSettings().audioOutputMode
  → MIDI 模式: _midiService.sendNoteOn()
  → 本机模式: _audioSynth.noteOn()

PianoKeyboard._handleNoteDown()
  → 读取 AppSettings().audioOutputMode
  → MIDI 模式: _midiService.sendNoteOn()
  → 本机模式: _synthService.noteOn()

ScoreViewPage.initState()
  → 读取 AppSettings().showKeyboardDefault
  → 播放时 _playState.isPlaying && _showKeyboard 显示键盘
```
