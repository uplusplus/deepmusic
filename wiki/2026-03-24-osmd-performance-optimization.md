# 2026-03-24 OSMD 乐谱渲染性能优化

## 优化目标

解决乐谱切换/加载慢的问题，建立性能度量体系，为后续优化提供数据支撑。

## 已完成的优化

### 1. 性能计时体系 (Performance Instrumentation)

在渲染管线的每个关键节点插入 `[PERF]` 计时日志，覆盖完整的端到端链路：

**Dart 侧 (`score_renderer.dart`)**
- `T0_render_start` — Dart 开始发送渲染指令
- `T2_js_dispatched` — Dart 消息已发出（经过 base64 编码）
- `T_webview_loaded` — WebView 页面加载完成
- `TOTAL` — 端到端总耗时（T0 → rendered 回调）

**JS 侧 (`index.html` / `handleMessageB64`)**
- `T3_js_receive` — JS 收到 base64 字符串
- `T_atob` — atob 解码完成（含 base64 长度）
- `T_bytes` — Uint8Array 构建完成
- `T4_decode` — TextDecoder UTF-8 解码完成
- `T5_osmd_load` — `osmd.load()` 完成
- `T6_osmd_render` — `osmd.render()` 完成（VexFlow SVG 生成）
- `JS_breakdown` — 分段耗时汇总：decode / load / render / total

**数据流向**
```
Dart base64.encode → WebView.postMessage → JS atob → Uint8Array → TextDecoder → JSON.parse → osmd.load → osmd.render → SVG
T0                  T2                    T3         T_atob       T_bytes        T4            T5           T6
```

### 2. XML 磁盘缓存 (Disk Cache)

**三级缓存策略：内存 → 磁盘 → 网络**

```
_loadScoreXml() 流程:
1. 内存缓存 (_xmlCache Map) → 命中直接返回 (~0ms)
2. 磁盘缓存 (getApplicationCacheDirectory/score_xml/{id}.xml) → 命中回填内存缓存后返回
3. 服务端下载 → 写入内存缓存 + 异步写入磁盘缓存
```

- 首次加载后，后续切换同一首乐谱直接从磁盘读取，无需网络请求
- 磁盘写入异步执行，不阻塞 UI
- 缓存目录：`{app_cache}/score_xml/{scoreId}.xml`

**涉及文件**
- `mobile/lib/features/score/pages/score_view_page.dart` — `_loadScoreXml()` 改造 + `_getCacheFile()` / `_saveToDiskCache()` 新增

### 3. 分页渲染支持 (Paginated Rendering)

**新增 JS 端分页能力**，支持将大乐谱按小节范围分批渲染：

- `render(xml, measuresPerPage)` — 首次渲染时指定每页小节数
- `renderPage(page)` — 翻页时不重新加载 XML，只切换 `MinMeasureToDrawIndex` / `MaxMeasureToDrawIndex` 并重新 `osmd.render()`
- 翻页性能：跳过 XML 解析 + `osmd.load()`，只执行 VexFlow SVG 生成

**Dart 侧**
- `ScoreRenderer` 新增 `measuresPerPage` 参数
- 新增 `renderPage(int page)` 方法供外部调用
- `ScoreRenderInfo` 扩展：`totalMeasures` / `page` / `totalPages`

**适用场景**
- 长乐谱（100+ 小节）一次性渲染 SVG 过大，导致 WebView 内存压力
- 用户只需看当前段落，分页可显著减少单次渲染量

### 4. 独立性能测试页

- `mobile/assets/osmd/benchmark.html` — 独立 OSMD 性能测试，内置 3 首不同规模的乐谱
- 可脱离 App 在浏览器中测试 OSMD 渲染性能基准

## 性能数据参考

（待补充：真机实测数据）

典型渲染管线各阶段耗时量级：
| 阶段 | 预估耗时 | 瓶颈程度 |
|------|---------|---------|
| base64 编码 (Dart) | 5-20ms | 低 |
| WebView 传输 | 1-5ms | 低 |
| atob + Uint8Array | 5-30ms | 中（大 XML） |
| TextDecoder UTF-8 | 5-15ms | 低 |
| osmd.load() | 100-500ms | **高** |
| osmd.render() (VexFlow) | 200-800ms | **高** |

**主要瓶颈：`osmd.load()` + `osmd.render()`**，占总耗时 90%+。

## 下一步优化方向

1. **分页渲染落地** — 将 `measuresPerPage` 接入 `ScoreViewPage`，长乐谱自动分页
2. **预加载机制** — 后台预渲染相邻页面，翻页零等待
3. **XML 压缩** — base64 前先 gzip 压缩，减少传输量
4. **OSMD 版本升级** — 评估新版 OSMD 的渲染性能改进
5. **WebWorker 解码** — 将 atob + TextDecoder 移至 Worker 线程

## 涉及文件

| 文件 | 改动 |
|------|------|
| `mobile/assets/osmd/index.html` | 性能计时 + 分页渲染 + measure range 应用 |
| `mobile/lib/features/score/widgets/score_renderer.dart` | 性能计时 + measuresPerPage 参数 + renderPage 方法 |
| `mobile/lib/features/score/pages/score_view_page.dart` | 三级缓存 (内存/磁盘/网络) |
| `mobile/assets/osmd/benchmark.html` | 独立性能测试页（新增） |
| `mobile/lib/data/services/api_client.dart` | API base URL 更新 |
