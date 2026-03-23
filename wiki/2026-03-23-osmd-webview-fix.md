# 2026-03-23 OSMD WebView 渲染稳定性修复

## 概述

修复乐谱查看页 WebView 渲染相关的多个问题：初始化时 OSMD 报错、切谱时白屏闪烁、打开乐谱缓慢等。经历了多轮调试，最终定位到 OSMD 库构造函数内部的 `autoResize` 机制是根因。

---

## 1. 问题描述

### 1.1 OSMD 初始化报错
- 首次进入乐谱页面时 100% 出现 SnackBar 报错：`"OSMD: Before render, please load a MusicXML file"`
- 渲染完成后报错消失，但用户体验很差

### 1.2 切谱时白屏闪烁
- 切换乐谱时，标题变了但旧谱子内容还显示着
- WebView 每次切谱都重建，加载时间 1-2 秒

### 1.3 打开乐谱缓慢
- 有缓存的乐谱打开也需要数秒
- 主要原因是 WebView 每次重建都要重新初始化 OSMD + CJK 字体

---

## 2. 调试过程

### 2.1 第一轮：WebView 保活 + AnimatedOpacity（失败）

**方案：** 切谱时不销毁 WebView，用 `AnimatedOpacity` 淡入新内容。

**结果：** AnimatedOpacity 在 opacity=0 时 WebView 仍然初始化（只是看不见），加了 300ms 动画延迟反而更慢。而且每次切谱仍把 `_xmlContent` 设为 null，导致 ScoreRenderer 被移除，WebView 重建。

### 2.2 第二轮：JS 侧 MaxMeasureToDrawIndex 渐进渲染（失败）

**方案：** 利用 OSMD 的 `MaxMeasureToDrawIndex` 属性，首次只渲染 25 小节，滚动时追加。

**结果：** `load()` 仍然解析完整 XML（不可跳过），渲染阶段虽限制了小节数但 `render()` 每次重绘全部 SVG，滚动追加时卡顿。

### 2.3 第三轮：Dart 侧 XML 拆分（搁置）

**方案：** Dart 侧拆分 MusicXML，首次只发前 20 小节，渐进追加。

**风险分析：**
- 字符串拼接不安全，多声部 XML 可能拼错位置
- 跨片段的连线（tie/slur）可能损坏
- 每次追加都重解析整个累积 XML

**结论：** 风险大于收益，搁置。

### 2.4 第四轮：WebView 保活 + Loading 遮罩（部分成功）

**方案：**
- `_switchScore` 不再清空 `_xmlContent`，WebView 保持存活
- `_showLoadingOverlay` 标志 + 白色遮罩 + Spinner 覆盖旧内容
- 新 XML 加载后通过 `didUpdateWidget` 发送给已有的 WebView
- `onRendered` 回调触发后隐藏遮罩

**结果：** 切谱速度提升明显（WebView 不重建），但初始化报错仍存在。

### 2.5 第五轮：定位 "Before render" 错误根因

通过添加 JS 日志转发到 Flutter，抓取到关键日志序列：

```
02:23:11.643  Score render error: OSMD init failed: OSMD: Before render...  ← 错误先到
02:23:11.645  [INFO:CONSOLE(52)] Uncaught (in promise) Error: OSMD: Before render...  ← 来自 OSMD 库 line 52
02:23:11.729  [OSMD] CJK font loaded  ← 字体加载完
02:23:11.786  [OSMD] render() #1  ← 我们的 render 这才开始
```

**关键发现：** 错误在我们的 `render()` 被调用**之前**就已触发。来源是 OSMD 库内部代码（minified，line 52）。

### 2.6 逐个排查

| 尝试 | 方案 | 结果 |
|------|------|------|
| 1 | JS render 防重入 + 排队 | 未解决，错误不在 render 调用链中 |
| 2 | init() 正确 Promise 化 | 修复了一个 bug，但根因未解决 |
| 3 | onWebResourceError 静默处理 | 修复了 favicon 404 等干扰 |
| 4 | ResizeObserver 加 graphic 检查 | 修复了一个竞态，但根因未解决 |
| 5 | OSMD autoResize: false | **被 OSMD 忽略**，构造时仍触发内部 render |
| 6 | 实例级 render patch（构造后） | 太晚了，构造函数内部已调完 render |
| 7 | **Prototype 级 render patch（构造前）** | ✅ 解决 |

### 2.7 最终根因

**OSMD 构造函数内部同步调用 `this.render()`。**

当 `new OpenSheetMusicDisplay(container, options)` 执行时，`autoResize` 设置在构造函数内部触发了一次 `this.render()`。此时：
- `this.graphic` 为 null（还没调 `load()`）
- OSMD 内部的 `render()` 检查 `if (!this.graphic) throw new Error("Before render...")`
- 异常被 OSMD 捕获，通过 `sendToFlutter('error', ...)` 发送到 Flutter
- 同时作为未处理 Promise rejection 抛出

`autoResize: false` 无效是因为 OSMD 构造函数可能忽略了这个选项，或在检查之前就触发了。

---

## 3. 最终修复方案

### 3.1 Prototype 级 render patch（根因修复）

```javascript
// 在创建 OSMD 实例之前，先 patch 原型方法
var OSDMRender = opensheetmusicdisplay.OpenSheetMusicDisplay.prototype.render;
opensheetmusicdisplay.OpenSheetMusicDisplay.prototype.render = function() {
  if (!this.graphic) {
    return Promise.resolve();  // 静默跳过
  }
  return OSDMRender.call(this);
};
```

这样构造函数内部调 `this.render()` 时，走的是守卫版本，graphic 为 null 就安全返回。

### 3.2 WebView 切谱保活

- `_switchScore` 不再清空 `_xmlContent`（保留旧内容防止 WebView 销毁）
- 新 XML 加载后，`didUpdateWidget` 检测到变化 → `_renderScore()` 发送新内容
- 已有的 WebView 实例接收新 XML → `osmd.load()` + `osmd.render()`
- 省去 WebView 初始化（1-2 秒）+ CJK 字体注入（0.5 秒）

### 3.3 切谱 Loading 遮罩

```dart
// _switchScore
setState(() {
  _showLoadingOverlay = true;  // 白色遮罩盖住旧内容
});

// _buildScoreRenderer
if (_showLoadingOverlay)
  Positioned.fill(child: Container(color: Colors.white, child: Spinner...))

// onRendered 回调
setState(() {
  _showLoadingOverlay = false;  // 渲染完，遮罩消失
});
```

### 3.4 JS render 防重入 + 排队

```javascript
var _rendering = false;
var _pendingXml = null;

async function render(xmlString) {
  if (_rendering) {
    _pendingXml = xmlString;  // 排队，只保留最新
    return;
  }
  _rendering = true;
  try { ... } finally {
    _rendering = false;
    if (_pendingXml) {
      var next = _pendingXml;
      _pendingXml = null;
      render(next);  // 自动执行排队任务
    }
  }
}
```

### 3.5 init() Promise 化

```javascript
function init() {
  return new Promise(function(resolve, reject) {
    requestAnimationFrame(function() {
      try {
        osmd = new opensheetmusicdisplay.OpenSheetMusicDisplay(...);
        // ...
        resolve();
      } catch (e) {
        reject(e);
      }
    });
  });
}
```

之前 `init()` 从不 resolve/reject，`await init()` 拿到 undefined 立刻返回，osmd 还没创建。

---

## 4. 涉及文件

| 文件 | 改动 |
|------|------|
| `mobile/assets/osmd/index.html` | Prototype render patch、init() Promise 化、render 防重入、ResizeObserver graphic 检查、autoResize: false |
| `mobile/lib/features/score/pages/score_view_page.dart` | WebView 保活（不 null _xmlContent）、_showLoadingOverlay 遮罩、移除 XML 拆分代码 |
| `mobile/lib/features/score/widgets/score_renderer.dart` | onWebResourceError 静默、移除 dataReady 参数 |
| `mobile/lib/features/practice/pages/practice_page.dart` | 移除 dataReady 参数 |

---

## 5. 教训

1. **不要急着改** — 连续多个方案没验证清楚就动手，浪费了大量时间
2. **不要用过滤掩盖错误** — JOY 明确要求修根因而不是 filter
3. **读日志找真实调用链** — 加了 JS→Flutter 日志转发后才定位到错误发生在 render #1 之前
4. **构造函数可能有副作用** — OSMD 的构造函数内部调了 render()，这是一个隐蔽的行为
5. **Prototype patch 必须在构造之前** — 实例级 patch 对构造函数内部调用无效
6. **Promise 不会自动 resolve** — `function init() { requestAnimationFrame(...) }` 返回 undefined，不是 Promise

---

## 6. 萨蒂 Gymnopédie No.1 加载失败修复

### 问题

萨蒂《裸体舞曲第一号》（Erik_Satie_-_Gymnopedie_No.1.xml）加载时报错：

```
Cannot read properties of undefined (reading 'TempoExpressions')
```

### 原因

- XML 文件由 MuseScore 1.3 导出（MusicXML 2.0）
- 文件中没有任何 `<direction>` 速度标记
- OSMD 渲染时内部需要访问 `TempoExpressions` 数据，找不到 → undefined → 报错

### 修复

在第一个 `<measure>` 的 `<print>` 元素后添加速度标记：

```xml
<direction placement="above">
  <direction-type>
    <metronome parentheses="no">
      <beat-unit>quarter</beat-unit>
      <per-minute>69</per-minute>
    </metronome>
  </direction-type>
  <sound tempo="69"/>
</direction>
```

♩=69 是萨蒂原谱的建议速度。修改文件：`server/uploads/scores/Erik_Satie_-_Gymnopedie_No.1.xml`

### 教训

- MuseScore 1.x 导出的 MusicXML 可能缺少 OSMD 需要的元数据（速度、力度等）
- 遇到 OSMD 渲染错误时，先检查 XML 是否包含 OSMD 期望的标准元素
- `_xmlCache` 是内存缓存，改 server 端文件后需要杀掉 app 重开才能加载新版本
