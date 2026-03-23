# MIDI 格式直接支持 — 可行性分析

> 日期: 2026-03-22
> 状态: TODO — 等整体稳定后开发

## 背景

当前乐谱系统完全基于 MusicXML（五线谱），从解析、渲染到练习全链路依赖 XML 格式。
考虑是否及如何支持 MIDI（.mid）格式作为额外的乐谱来源。

## 核心差异

| 维度 | MusicXML | MIDI |
|------|----------|------|
| 本质 | 乐谱数据（记谱意图） | 演奏数据（按键事件） |
| 音高 | step + alter + octave | 纯 MIDI note number（无升降号写法） |
| 谱表 | 明确 staff 标注 | 无，需算法推断（不可靠） |
| 小节 | 明确 measure 边界 | 需从拍号推算（变拍号场景易出错） |
| 五线谱视觉 | 完整（符干、连音线等） | 无 |
| 文件格式 | 文本 XML | 二进制 |

## MIDI 能提供

- ✅ 音高 (note number) + 力度 (velocity)
- ✅ 精确时间轴 (ticks → ms)
- ✅ 速度变化 (tempo meta events)
- ✅ 拍号 / 调号 (meta events)

## MIDI 缺失

- ❌ 谱表分配（右/左手）— 需算法推断
- ❌ 升降号写法（C# vs Db 都是 61）
- ❌ 五线谱视觉信息
- ❌ 歌词、表情记号

## 方案对比

### 方案 A：MIDI → MusicXML 转换后走现有流程
- 复用现有全部练习链路
- 转换有损，复杂曲子质量差
- 需要引入转换工具依赖

### 方案 B：MIDI → 内部 Score 模型 + Piano Roll 渲染 ✅ 推荐
- 写 `MidiParser` 输出同 `MusicXmlParser` 一致的 `Score` 对象
- 渲染改用 Piano Roll（钢琴卷帘）而非五线谱
- 练习功能（ScoreFollower、NoteEvaluator）完全复用
- 数据无损，Dart 有现成 MIDI 解析库
- 五线谱继续保留给 MusicXML 用户

### 方案 C：MIDI 仅用于练习模式，不渲染乐谱
- 改动最小，但缺少视觉反馈
- 体验打折

## 推荐方案 B 实施要点

1. **MidiParser** (~200行)
   - 解析 MIDI 文件，提取 note on/off 事件
   - 从 tempo track 计算 ms 时间轴
   - 从 time signature meta events 推算小节边界
   - 输出 `Score` 对象（Part → Measure → Note）
   - 音高用 enharmonic 优先策略（尽量用升号）

2. **Piano Roll 渲染组件** (~300行)
   - Canvas/CustomPainter 绘制
   - 纵轴 = 音高（88 键），横轴 = 时间
   - 支持小节线、拍号标注
   - 支持高亮当前音符 + 循环区间
   - 支持缩放和滚动

3. **服务端** (~50行)
   - 支持 `.mid` 文件上传
   - API 返回格式标记（musicxml / midi）

4. **预估工作量**: 1-2 天

## 依赖

- Dart MIDI 解析: `midi` 或 `dart_midi` 包
- Piano Roll 可用 `CustomPainter` 纯 Canvas 实现，无额外依赖

## 备注

- MIDI 来源丰富（Musescore 导出、网络资源），能快速扩充曲库
- 与 MusicXML 并行支持，用户可选择格式
- 等整体稳定后再开发，避免打断当前迭代
