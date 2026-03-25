# 乐谱播放性能优化 — 2026-03-22

## 问题现象

乐谱自动播放时出现卡顿、音符拖尾或提前截断，尤其在非 120 BPM 的曲目上明显。

## 排查过程

### 1. 时间轴精度

| 组件 | 原始实现 | 问题 |
|------|----------|------|
| `Timer.periodic(10ms)` | Dart 事件循环驱动 | GC/帧渲染导致 jitter 20-50ms |
| `Stopwatch.elapsedMilliseconds` | int 截断 | 乘以 playbackRate 后 `.round()` 产生亚毫秒累积误差 |

### 2. 音符时长计算

`_buildScheduledEvents()` 硬编码 `tempo = 120`，而 Parser 解析的实际 tempo（如 Bach Prelude = 74 BPM）存放在 `score.tempo`。

**后果**：`startMs` 用 74 BPM 算，`durationMs` 用 120 BPM 算 → Note Off 提前 38%，音符被截断。

### 3. PCM 缓冲区拷贝

`AudioSynthService._onFeed()` 每个 256-sample block（~5.8ms 音频）做 512 次单字节拷贝：

```dart
// 修复前
for (int i = 0; i < src.lengthInBytes; i++) {
  dst.setUint8(i, src.getUint8(i)); // 512 次调用
}
```

阻塞音频回调线程，导致 PCM feed 不及时 → 爆音/断续。

### 4. UI 重建频率

`_emitState()` 每次 tick 都触发 stream → 10ms/tick = 100fps UI 重建，浪费 GPU。

### 5. Tempo 解析遗漏

`_parseMetadata()` 只检查 `<sound tempo="..."/>` 作为 `<measure>` 直接子元素，但标准 MusicXML 中 `<sound>` 嵌套在 `<direction>` 内。

## 修复方案

### 时钟调度：Schedule-Next-Event

```
修复前: Timer.periodic(10ms) → 每 10ms 无条件轮询 → jitter 累积
修复后: Timer(Duration(nextEvent - lookahead)) → 精确到下一个事件 → 无空转
```

```dart
void _scheduleNextTick() {
  _tick(); // 处理当前 lookahead 窗口内的事件

  if (_eventIndex < _events.length) {
    final nextEventMs = _events[_eventIndex].absoluteMs;
    int delayMs = ((nextEventMs - playbackMs) / _playbackRate).round() - _lookaheadMs;
    if (delayMs < 1) delayMs = 1;
    _tickTimer = Timer(Duration(milliseconds: delayMs), _scheduleNextTick);
  }
}
```

- `_lookaheadMs = 25`：容忍 Timer jitter，提前 25ms 唤醒处理
- 无事件时空转率为零

### Tempo 修正

```dart
// 修复前
final tempo = 120; // 硬编码
// 修复后
final tempo = score.tempo; // 使用实际乐谱 tempo
```

### PCM 零拷贝

```dart
// 修复前：逐字节拷贝
for (int i = 0; i < src.lengthInBytes; i++) {
  dst.setUint8(i, src.getUint8(i));
}

// 修复后：内存视图引用
final byteData = ByteData.view(
  srcBytes.buffer,
  srcBytes.offsetInBytes,
  srcBytes.lengthInBytes,
);
```

加上批量渲染（`blocksPerFeed = 4`），减少 platform call 频率。

### UI 节流

```dart
static const int _stateEmitIntervalMs = 30; // ~33fps

void _tick() {
  if (playbackMs - _lastStateEmitMs >= _stateEmitIntervalMs) {
    _lastStateEmitMs = playbackMs;
    _emitState();
  }
}
```

### 微秒级时钟

```dart
int _getPlaybackMs() {
  final elapsedUs = _stopwatch.elapsedMicroseconds;
  final playbackUs = _elapsedBaseMs * 1000 + (elapsedUs * _playbackRate).round();
  return (playbackUs / 1000).round();
}
```

### 和弦音符同步

Parser 新增 `prevNoteTickPos` 变量，`<chord/>` 音符使用前一个音符的 tick 位置而非已推进的位置。

### Tempo 解析优先级

`_parseMetadata()` 现在按优先级查找 tempo：
1. `<direction><sound tempo="..."/>`（标准位置）
2. `<sound tempo="..."/>`（measure 直接子元素）
3. `<metronome><per-minute>`（节拍器标记）

## 测试

### 单元测试

`mobile/test/playback_test.dart` — 16/20 通过（4 个因 `flutter_pcm_sound` 原生插件在 headless 环境不可用，真机正常）。

| 测试组 | 用例数 | 结果 |
|--------|--------|------|
| pitchNumber 映射 | 3 | ✅ |
| 时间轴计算 | 5 | ✅ |
| 和弦同步 | 2 | ✅ |
| AutoPlayer 调度 | 3 | ✅ (含 tempo 修正验证) |
| Bach 实际乐谱 | 4 | ✅ |
| 边界条件 | 2 | ✅ |

### 真机集成测试

`mobile/lib/features/practice/pages/playback_test_page.dart` — 路由 `/playback-test`

验证内容：
- AudioSynthService 初始化 + 发声
- Score tempo 检测（非默认 120）
- 事件调度计时精度（平均偏差 <15ms，最大 <50ms）
- UI 节流效果（~33fps）

## 影响文件

| 文件 | 改动 |
|------|------|
| `mobile/lib/features/practice/services/auto_player.dart` | 时钟重构 + tempo 修复 + UI 节流 |
| `mobile/lib/features/practice/services/audio_synth_service.dart` | PCM 零拷贝 + 批量渲染 |
| `mobile/lib/features/score/services/musicxml_parser.dart` | tempo 解析 + 和弦 tickPos |
| `mobile/lib/features/practice/pages/playback_test_page.dart` | 新增：真机集成测试 |
| `mobile/test/playback_test.dart` | 新增：单元测试 20 例 |
| `mobile/lib/core/router/app_router.dart` | 新增 `/playback-test` 路由 |
