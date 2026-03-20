# DeepMusic - 产品需求文档 (PRD)

> 版本: 1.4 | 更新: 2026-03-20 20:38

---

## 1. 产品愿景

DeepMusic 是一个 AI 驱动的音乐学习助手，重新定义人学习音乐、创作音乐和演奏音乐的方式。

Phase 1 聚焦于**钢琴学习**，以蓝牙 MIDI 数字钢琴为核心输入设备，提供实时乐谱跟随、练习评估和智能曲谱库功能。

---

## 2. 需求决策记录

### 2026-03-15 需求讨论

| 问题 | 决策 |
|------|------|
| 乐谱库规模 | 30 首热门曲谱（公有领域） |
| 乐谱版权 | 仅使用 Public Domain 乐谱，来源 IMSLP/Mutopia |
| 评估维度 | 音准、节奏（Phase 1 不含力度/表情评估） |
| 技术栈 | Flutter (跨平台) + Express/TypeScript 后端 |
| Web 端 | 需要：用户管理、乐谱服务、练习记录 API |
| HarmonyOS | 延后至 Phase 2 |
| 目标设备 | Yamaha P125（蓝牙 MIDI），后续扩展其他型号 |
| 团队 | 全 AI 开发 |
| AI 评估 | Phase 1 基于规则的简化评估，Phase 3 引入大模型 |
| 乐谱渲染 | Phase 1 用 OSMD (WebView)，Phase 2 考虑自定义 Flutter 渲染 |
| 音频引擎 | 不使用独立音频引擎，MIDI 直接提供音符号 |

---

## 3. Phase 1 范围

### 3.1 目标平台

| 平台 | 状态 | 备注 |
|------|------|------|
| iOS (iPhone/iPad) | ✅ Phase 1 | 需要 macOS 构建 |
| Android | ✅ Phase 1 | 主要开发/测试平台 |
| Web Admin | ✅ Phase 1 | 后端 API + 简单管理 |
| HarmonyOS | ⏳ Phase 2 | 延后 |

### 3.2 目标设备

- **主设备**: Yamaha P125（蓝牙 BLE MIDI + USB MIDI）
- **连接方式**: 蓝牙 4.0+ BLE MIDI / USB OTG MIDI
- **兼容性**: Phase 1 测试 P125（蓝牙 + USB 双模式），Phase 2 扩展其他型号

### 3.3 核心功能需求

#### F1: MIDI 连接（蓝牙 + USB）

**蓝牙 BLE MIDI:**
- **F1.1** 自动扫描附近 BLE MIDI 设备
- **F1.2** 连接指定设备（Yamaha P125）
- **F1.3** 断线自动重连（最多 3 次，间隔 2 秒）
- **F1.4** 连接状态实时显示（断开/连接中/已连接/错误）
- **F1.5** 断开连接

**USB MIDI:**
- **F1.6** 自动检测 USB MIDI 设备（OTG 连接）
- **F1.7** 支持热插拔（设备接入/拔出自动识别）
- **F1.8** USB 连接优先于蓝牙（当两者同时可用时）
- **F1.9** USB 连接状态实时显示

**通用:**
- **F1.10** 统一的 MIDI 事件分发（蓝牙/USB 数据合并为统一 Stream）
- **F1.11** 连接方式切换（蓝牙 ↔ USB）无需重启 App

**验收标准**: 蓝牙连接 5 秒内完成，USB 连接 2 秒内识别，MIDI 事件延迟 < 50ms（蓝牙）/ < 20ms（USB）。

#### F2: 实时音符识别

- **F2.1** 接收 MIDI Note On / Note Off 事件
- **F2.2** 实时显示当前弹奏音符名称
- **F2.3** 记录音符的力度值（velocity）
- **F2.4** 支持多音同时识别（和弦）

**验收标准**: 音符识别准确率 100%（MIDI 信号无误差），端到端延迟 < 100ms。

#### F3: 乐谱跟随（核心功能）

- **F3.1** 根据用户弹奏实时定位乐谱位置
- **F3.2** 高亮当前小节和当前音符
- **F3.3** 自动翻页：在当前页最后一个音符前自动翻页
- **F3.4** 手动翻页支持（左右滑动）
- **F3.5** 支持跳过错误继续跟随（容错机制）
- **F3.6** 支持和弦匹配（多个音符同时弹奏）

**验收标准**: 跟随准确率 > 95%，翻页时机准确，容错跳过响应 < 1 秒。

#### F4: 练习评估

- **F4.1** 音准检测：弹奏音符 vs 乐谱音符对比
- **F4.2** 节奏检测：弹奏时间 vs 乐谱时间对比
- **F4.3** 评估容忍度可配置（默认 ±200ms）
- **F4.4** 评分报告：音准分、节奏分、综合分、等级（S/A/B/C/D/F）
- **F4.5** 练习记录持久化（本地 + 服务端）

**验收标准**: 评估结果与人工判断一致率 > 90%，评分区间合理。

#### F5: 乐谱库

- **F5.1** 30 首无版权曲谱（MusicXML 格式）
- **F5.2** 按分类浏览：初级练习曲、古典入门、流行轻音乐
- **F5.3** 按难度筛选：初级 / 中级 / 高级
- **F5.4** 搜索功能（标题、作曲家）
- **F5.5** 收藏功能
- **F5.6** 乐谱详情页（标题、作曲家、难度、时长、调号、拍号）

#### F6: 乐谱渲染

- **F6.1** MusicXML 解析（支持 .xml / .musicxml / .mxl）
- **F6.2** OSMD + WebView 渲染五线谱
- **F6.3** 支持高亮控制（小节级 + 音符级）
- **F6.4** 支持缩放和滚动

#### F7: 用户系统

- **F7.1** 注册 / 登录（邮箱 + 密码）
- **F7.2** 个人资料编辑
- **F7.3** 练习历史查看
- **F7.4** 收藏列表

#### F8: 区间循环练习

用户在练习过程中可选择乐谱的任意一段小节区间，ScoreFollower 在该区间内循环运行，用于攻克难点段落。

**交互设计:**
- **F8.1** 练习页底部控制面板新增「区间选择」按钮
- **F8.2** 区间选择面板: 输入/滑动选择起始小节和结束小节
- **F8.3** 乐谱上以半透明色块高亮标注选定区间范围
- **F8.4** 支持拖拽调整区间: 在 OSMD 乐谱上长按拖动选择
- **F8.5** 循环模式开关: 开启后 ScoreFollower 到达区间末尾自动跳回起始小节
- **F8.6** 循环次数显示: 「第 3/5 次循环」或「无限循环」
- **F8.7** 退出循环模式: 点击「全区练习」或关闭循环开关

**评估逻辑:**
- **F8.8** 循环练习的评估独立于全局: 每次循环生成独立评分
- **F8.9** 循环结束后显示最佳成绩和趋势对比 (第 1 次 vs 最后 1 次)
- **F8.10** 区间练习记录作为子记录关联到完整练习会话

**技术要点:**
- ScoreFollower 新增 `setLoopRange(startMeasure, endMeasure)` 和 `clearLoopRange()`
- 循环时 `_currentGroupIndex` 在区间末尾重置为区间起始对应的 group index
- PracticeProgress 新增 `loopCycle`, `loopBestScore` 字段
- OSMD 高亮区间: 通过 JavaScript 注入自定义 SVG 矩形覆盖区间小节

**验收标准**: 区间选择响应 < 500ms，循环跳转无卡顿 (< 100ms)，每次循环评分正确。

#### F9: 自动播放乐谱

用户可在乐谱库中选择任意乐谱进行自动播放试听，无需连接 MIDI 键盘即可预览曲目。

**交互设计:**
- **F9.1** 乐谱库每首乐谱新增「播放」按钮 (▶️ 图标)
- **F9.2** 乐谱详情页新增「试听」入口
- **F9.3** 播放器界面: 播放/暂停/停止 + 进度条 + 当前小节显示
- **F9.4** 变速控制: 0.5x ~ 2.0x，步进 0.25x
- **F9.5** 播放时 OSMD 实时高亮跟随当前小节
- **F9.6** 支持从指定小节开始播放 (点选乐谱)
- **F9.7** 后台播放: 切换到其他页面时继续播放 (可选)

**音频引擎:**
- **F9.8** 使用 MIDI 合成: 通过 MidiService.sendNoteOn/sendNoteOff 按时间序列发送 MIDI 音符
- **F9.9** 从 Score 对象的 Note 列表生成 MIDI 事件序列 (noteOn + noteOff + 时间戳)
- **F9.10** 速度控制: playbackRate 乘以每个事件的时间偏移
- **F9.11** 支持和弦: 同一 startMs 的多个音符同时发送
- **F9.12** 力度: 默认 velocity=80，后续支持从乐谱提取

**技术要点:**
- 新建 `AutoPlayer` 类: Stopwatch + Timer 驱动的 MIDI 事件调度器
- `List<ScheduledMidiEvent>` 从 Score.allNotes 预计算 (noteNumber + velocity + absoluteMs)
- 播放调度: 每 10ms tick 检查是否有待发送事件，批量发送同一时间点的事件
- 变速: `actualMs = absoluteMs / playbackRate`
- OSMD 跟随: 复用小节位置检测，仅做位置推进不做音符匹配

**验收标准**: 播放启动延迟 < 200ms，变速实时生效 (< 100ms)，和弦同时发声无偏差。

### 3.4 非功能需求

| 类别 | 需求 |
|------|------|
| **性能** | MIDI 事件端到端延迟 < 100ms，乐谱渲染首次加载 < 2s |
| **兼容性** | Android 8.0+，iOS 14+ |
| **离线** | 内置乐谱可离线使用，练习记录离线缓存同步 |
| **安全** | 密码 bcrypt 哈希，JWT 认证，API rate limit |
| **可用性** | 支持横屏/竖屏，暗色模式 |

---

## 4. 数据流设计

### 4.1 练习核心数据流

```
用户弹琴 → BLE MIDI → MidiService (Dart)
                          │
                          ├─→ MidiEvent Stream ─→ PracticePage UI (实时音符显示)
                          │
                          └─→ ScoreFollower.processMidiEvent()
                                │
                                ├─→ 音符匹配 (pitchNumber 对比)
                                │     ├─ 匹配成功 → 前进到下一个音符
                                │     ├─ 匹配失败 → 容错计数器
                                │     └─ 容错超限 → 标记为遗漏，继续前进
                                │
                                ├─→ NoteEvaluator.evaluate()
                                │     ├─ 音准评估
                                │     ├─ 节奏评估 (时间偏差)
                                │     └─ 返回 NoteEvaluation
                                │
                                └─→ PracticeProgress Stream ─→ UI 更新
                                      ├─ 当前位置高亮
                                      ├─ 翻页检测
                                      └─ 完成度统计
```

### 4.2 练习记录数据流

```
PracticeSession.start()
    │
    ├── 记录 startTime
    ├── 创建本地 PracticeRecord
    └── 调用 POST /api/practice/start
    
PracticeSession.end()
    │
    ├── 收集所有 NoteEvaluation
    ├── NoteEvaluator.generateReport()
    ├── 本地持久化 PracticeReport
    └── 调用 POST /api/practice/end (上传报告)
```

### 4.3 乐谱加载数据流

```
ScoreLibraryPage
    │
    └── GET /api/scores (分页 + 筛选)
          └── 返回 Score 列表 (元数据)
              
ScoreViewPage
    │
    ├── GET /api/scores/:id (详情)
    ├── GET /api/scores/:id/xml (MusicXML 文件)
    └── WebView + OSMD 渲染乐谱
```

---

## 5. 30 首曲谱清单

### 初级练习曲 (10 首)
| # | 曲目 | 作曲家 | 难度 |
|---|------|--------|------|
| 1 | 拜厄练习曲 No.60 | Beyer | 初级 |
| 2 | 拜厄练习曲 No.68 | Beyer | 初级 |
| 3 | 车尔尼 Op.599 No.11 | Czerny | 初级 |
| 4 | 车尔尼 Op.599 No.14 | Czerny | 初级 |
| 5 | 车尔尼 Op.599 No.18 | Czerny | 初级 |
| 6 | 布格缪勒 Op.100 No.1 题词 | Burgmüller | 初级 |
| 7 | 布格缪勒 Op.100 No.2 阿拉伯风格曲 | Burgmüller | 初级 |
| 8 | 布格缪勒 Op.100 No.3 牧歌 | Burgmüller | 初级 |
| 9 | 小星星变奏曲主题 | Mozart | 初级 |
| 10 | 欢乐颂主题 | Beethoven | 初级 |

### 古典入门 (10 首)
| # | 曲目 | 作曲家 | 难度 |
|---|------|--------|------|
| 11 | 致爱丽丝 | Beethoven | 中级 |
| 12 | 小步舞曲 BWV Anh.114 | Petzold/Bach | 初级 |
| 13 | 小步舞曲 BWV Anh.115 | Petzold/Bach | 初级 |
| 14 | 梦幻曲 Op.15 No.7 | Schumann | 中级 |
| 15 | 圣诞快乐变奏曲主题 | Beethoven | 初级 |
| 16 | G 大调小步舞曲 | Beethoven | 初级 |
| 17 | 二部创意曲 No.1 BWV 772 | Bach | 中级 |
| 18 | 二部创意曲 No.8 BWV 779 | Bach | 中级 |
| 19 | 小奏鸣曲 Op.36 No.1 第一乐章 | Clementi | 中级 |
| 20 | 小奏鸣曲 Op.36 No.3 第一乐章 | Clementi | 中级 |

### 流行/轻音乐 (10 首)
| # | 曲目 | 备注 | 难度 |
|---|------|------|------|
| 21 | 生日快乐 | 公有领域 | 初级 |
| 22 | 两只老虎 | 公有领域 | 初级 |
| 23-30 | *待补充* | 需收集无版权改编曲 | 初级-中级 |

> **注意**: 曲谱清单需在开发过程中与实际可用的 MusicXML 资源对齐，部分曲目可能需要自行转谱。

---

## 6. API 契约

### Auth
| 方法 | 路径 | 说明 | 请求体 | 响应 |
|------|------|------|--------|------|
| POST | `/api/auth/register` | 注册 | `{email, password, nickname}` | `{user, token}` |
| POST | `/api/auth/login` | 登录 | `{email, password}` | `{user, token}` |
| POST | `/api/auth/logout` | 登出 | - | `{success}` |

### Scores
| 方法 | 路径 | 说明 | 参数 | 响应 |
|------|------|------|------|------|
| GET | `/api/scores` | 列表 | `?page=&limit=&difficulty=&category=&search=` | `{scores[], pagination}` |
| GET | `/api/scores/:id` | 详情 | - | `{score}` |
| GET | `/api/scores/:id/xml` | 下载 MusicXML | - | XML 文件流 |
| POST | `/api/scores/:id/favorite` | 收藏 | - | `{success}` |
| DELETE | `/api/scores/:id/favorite` | 取消收藏 | - | `{success}` |

### Practice
| 方法 | 路径 | 说明 | 请求体 | 响应 |
|------|------|------|--------|------|
| POST | `/api/practice/start` | 开始练习 | `{scoreId}` | `{sessionId}` |
| POST | `/api/practice/:id/note` | 上传音符事件 | `{notes: NoteEvent[]}` | `{success}` |
| POST | `/api/practice/:id/end` | 结束练习 | `{report: PracticeReport}` | `{record}` |
| GET | `/api/practice/history` | 历史记录 | `?page=&limit=` | `{records[], pagination}` |
| GET | `/api/practice/stats` | 统计数据 | `?period=week\|month\|all` | `{stats}` |

### User
| 方法 | 路径 | 说明 | 响应 |
|------|------|------|------|
| GET | `/api/user/profile` | 个人资料 | `{user}` |
| PUT | `/api/user/profile` | 更新资料 | `{user}` |
| GET | `/api/user/favorites` | 收藏列表 | `{scores[]}` |
| GET | `/api/user/statistics` | 统计 | `{stats}` |

---

## 7. 风险与缓解

| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| iOS 开发需要 Mac | 高 | 使用 Codemagic / Bitrise 云构建 |
| 蓝牙 MIDI 设备兼容性 | 中 | Phase 1 聚焦 P125，封装适配层 |
| 乐谱渲染性能 | 中 | OSMD + WebView 方案成熟，Phase 2 考虑自定义渲染 |
| 音乐版权 | 高 | 仅用公有领域乐谱，IMSLP 来源 |
| MusicXML 资源不足 | 中 | 准备手工转谱工具，优先级曲目优先 |
| Flutter 跨平台差异 | 低 | 早期多平台测试，UI 适配层抽象 |

---

## 8. 待确认事项

- [ ] 最终 30 首曲谱确认（目前 19 首已导入）
- [ ] App 名称、Logo、品牌设计
- [ ] 服务器部署方案（阿里云 / 腾讯云 / Vercel）
- [ ] 隐私政策、用户协议
- [ ] 是否需要云同步练习记录
- [ ] 练习评估的容忍度阈值调优（通过用户测试）

---

*产品负责人: 项目团队 | 更新: 2026-03-20*
