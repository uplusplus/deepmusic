# 2026-03-23 练习按钮位置调整

## 问题

播放页面右下角有异常元素显示，影响美观。截图中可见红色文字出现在乐谱右下角区域。

## 排查过程

1. **误判方向：OSMD 渲染溢出** — 以为是 OSMD 渲染的歌词/指法标注溢出 WebView 容器
   - 尝试关闭 `RenderLyrics` / `RenderFingerings` / `RenderChordSymbols` → 用户指出这些是核心功能，不能关
   - 尝试 CSS `overflow: hidden` + JS 注入禁滚动 → 回退
   - 尝试搜索 XML 文件中的 "右侧" 文本 → 未找到
2. **误判方向：所有曲子都有** — 以为是 OSMD 通用问题
3. **真正根因：播放栏空间不足** — 练习按钮放在播放栏右下角，横向空间不够，导致按钮或相关布局溢出

## 解决方案

将「练习」按钮从播放栏底部移到 AppBar 右上角（收藏按钮旁边）。

## 修改文件

### `score_view_page.dart`

**AppBar actions 新增练习按钮：**
```dart
// 练习按钮
TextButton.icon(
  onPressed: () {
    _autoPlayer?.stop();
    Navigator.of(context).pushNamed(
      AppRouter.practice,
      arguments: {'scoreId': score.id},
    );
  },
  icon: const Icon(Icons.piano, size: 18),
  label: const Text('练习', style: TextStyle(fontSize: 14)),
  style: TextButton.styleFrom(
    foregroundColor: AppColors.primary,
    padding: const EdgeInsets.symmetric(horizontal: 8),
  ),
),
```

**播放栏移除练习按钮：** 删除了 `_buildPlayerBar` 中底部的 `ElevatedButton.icon` 练习按钮。

## 教训

- 先确认布局空间问题，不要直接猜渲染引擎的 bug
- "所有曲子都有" + "只有播放界面有" → 应该优先对比两个页面的 **Flutter 布局差异**，而不是去改 WebView/OSMD
- CSS overflow / JS 注入是最后手段，不是第一步
