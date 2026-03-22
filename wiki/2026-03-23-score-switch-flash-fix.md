# 2026-03-23 乐谱列表滚动位置重置修复

## 问题现象

在乐谱播放界面（横屏右侧/竖屏底部抽屉），滚动乐谱列表后点击切换乐谱，整个界面会闪烁重置，列表回到顶部。

## 分析过程

### 第一轮：以为是乐谱列表的问题

**假设**：`_EmbeddedScoreList` 的 ScrollController 在父级 rebuild 时被重置。

**尝试方案 1**：`_savedOffset` + `addPostFrameCallback` 恢复滚动位置
- 在 `build()` 中保存 offset，重建后用 `jumpTo` 恢复
- **结果**：有一帧延迟，仍然闪烁

**尝试方案 2**：把恢复逻辑从 `build()` 移到 `didUpdateWidget()`
- **结果**：仍然闪

**尝试方案 3**：给 ListView 加 `GlobalKey`
- 认为 GlobalKey 可以让 Flutter 复用 ListView 的 State
- **结果**：没用，因为 ListView 的 State 不是问题所在

**尝试方案 4**：给 `_EmbeddedScoreList` widget 本身加 `ValueKey`
- 确保父级 rebuild 时不销毁 `_EmbeddedScoreListState`
- **结果**：列表部分 OK，但整体仍然闪

### 第二轮：发现问题不在列表，在整个页面

用户反馈"感觉是整个界面重置了，都不只是乐谱列表的问题"。

**根因分析**：`_switchScore` 的调用链：

```
_switchScore()
  → setState({ _currentScoreId = 新ID })
  → build() 触发
  → ref.watch(scoreDetailProvider(新ID)) → AsyncLoading（新 ID 没缓存）
  → scoreAsync.when(loading: Scaffold(...)) → 全屏加载画面
  → 整页闪烁重置
```

**关键发现**：`ref.invalidate(scoreDetailProvider(newScore.id))` 后，provider 对新 ID 进入 `AsyncLoading`。`scoreAsync.hasValue` 为 false（新 ID 没有缓存值），所以 `requireValue` 无法使用。

### 第三轮：本地缓存 fallback

**最终方案**：引入 `_lastScore` 本地变量缓存上一首乐谱数据。

```dart
ScoreModel? _lastScore;

@override
Widget build(BuildContext context) {
  final scoreAsync = ref.watch(scoreDetailProvider(_currentScoreId));

  // 缓存乐谱数据
  if (scoreAsync.hasValue) {
    _lastScore = scoreAsync.requireValue;
  }

  // loading/error 时用缓存保持界面不闪
  if (!scoreAsync.hasValue && _lastScore != null) {
    return _buildScoreView(_lastScore!);
  }

  return scoreAsync.when(
    data: (score) => _buildScoreView(score),
    ...
  );
}
```

**效果**：
- `_switchScore` → provider `AsyncLoading` → `_lastScore` 有缓存 → 用旧数据渲染页面
- 只有 `_showLoadingOverlay` 覆盖旧内容，页面结构不动
- 新数据到达 → 正常渲染新乐谱
- 列表 ScrollController（通过 `ValueKey` 保持）不受影响

## 附带修复

- `_EmbeddedScoreList` 加 `ValueKey('embedded_score_list')` + `super.key`，确保父级 rebuild 时 State 不销毁
- `_ScoreListSheetContent` 的 `didUpdateWidget` 中添加滚动位置恢复逻辑（竖屏抽屉）
- 清理 `_ScoreListSheetContentState` 中的 debug print

## 涉及文件

- `lib/features/score/pages/score_view_page.dart`
