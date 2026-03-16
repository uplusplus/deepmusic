# DeepMusic - Phase 1 Requirements

## 需求决策记录

### 2026-03-15 需求讨论

| 问题 | 决策 |
|------|------|
| 乐谱库规模 | 30 首热门曲谱 |
| 乐谱版权 | 仅使用无版权乐谱 (Public Domain) |
| 评估维度 | 音准、节拍与谱子一致 |
| 技术栈 | Flutter (跨平台) + Web 后台 |
| Web 端 | 需要：用户管理、乐谱服务、Bug 跟踪 |
| HarmonyOS | 延后至二期 |
| 目标设备 | Yamaha P125 (蓝牙 MIDI) |
| 团队 | 全 AI 开发 |
| 上线时间 | 目标本月 (2026-03) |
| AI 评估 | 简化版规则评估 + 自动跟弹 + 自动翻页 |
| 第三方服务 | 先分析可用选项，暂不接入 |

---

## Phase 1 Scope (MVP)

### 目标平台
- ✅ iOS (iPhone/iPad)
- ✅ Android
- ⏳ HarmonyOS (Phase 2)
- ✅ Web Admin (用户管理、乐谱服务、Bug 跟踪)

### 目标设备
- 电钢琴: Yamaha P125 (蓝牙 MIDI)
- 扩展: 后续支持更多型号

### 核心功能

#### 1. 蓝牙 MIDI 连接
- 自动扫描附近 MIDI 设备
- 连接 Yamaha P125
- 断线重连机制
- 连接状态显示

#### 2. 实时音符识别
- 接收 MIDI 信号
- 实时显示当前音符
- 音符时值记录

#### 3. 乐谱跟随 (核心)
- 根据用户弹奏自动定位到乐谱位置
- 自动高亮当前小节/音符
- 自动翻页 (到达页面末尾前触发)
- 手动翻页备选

#### 4. 练习评估 (简化版)
- 音准检测: 弹奏音符 vs 乐谱音符
- 节奏检测: 弹奏时值 vs 乐谱时值
- 完成度统计: 正确率
- 简单评分报告

#### 5. 乐谱库
- 30 首无版权曲谱
- 分类浏览
- 收藏功能
- 下载到本地

---

## 技术栈

### 移动端 (Flutter)
```
Flutter 3.x
├── flutter_midi_command  # 蓝牙 MIDI
├── audioplayers          # 音频播放
├── provider / riverpod   # 状态管理
├── dio                   # 网络请求
└── sqflite               # 本地存储
```

### 乐谱渲染
```
选项:
1. OpenSheetMusicDisplay (OSMD) - Web/Flutter
2. VexFlow - Web
3. 自定义渲染引擎
```

### Web 后台
```
前端: Flutter Web 或 React
后端: Node.js / Python FastAPI
数据库: PostgreSQL / MongoDB
存储: 云存储 (OSS/S3)
```

---

## 第三方服务分析

### 乐谱 API
| 服务 | 说明 | 价格 |
|------|------|------|
| MuseScore API | 大量用户上传乐谱 | 需授权 |
| Music21 | Python 乐谱分析库 | 开源免费 |
| OpenSheetMusicDisplay | 乐谱渲染 | 开源免费 |

### MIDI 处理库
| 库 | 平台 | 说明 |
|---|---|---|
| flutter_midi_command | Flutter | 蓝牙/USB MIDI |
| Core MIDI | iOS | 原生 |
| Android MIDI API | Android | 原生 (API 23+) |

### 音频分析
| 服务 | 说明 | 价格 |
|------|------|------|
| Aubio | 开源音频分析 | 免费 |
| Essentia | 音频分析库 | 开源 |
| Librosa | Python 音频库 | 开源 |

---

## 开发里程碑

### Week 1: 基础架构
- [ ] Flutter 项目搭建
- [ ] 蓝牙 MIDI 连接 (Yamaha P125)
- [ ] 基础 UI 框架
- [ ] Web 后台初始化

### Week 2: 乐谱模块
- [ ] MusicXML 解析
- [ ] 乐谱渲染 (基础)
- [ ] 30 首曲谱导入
- [ ] 乐谱浏览 UI

### Week 3: 核心交互
- [ ] 实时音符识别
- [ ] 乐谱跟随逻辑
- [ ] 自动翻页
- [ ] 弹奏高亮

### Week 4: 评估 & 发布
- [ ] 音准检测
- [ ] 节奏检测
- [ ] 评分报告
- [ ] 内测 & Bug 修复
- [ ] App Store / Google Play 提交

---

## 待确认事项

- [ ] 30 首曲谱具体曲目列表
- [ ] 无版权乐谱来源确认
- [ ] App 名称、Logo、品牌设计
- [ ] 服务器部署方案
- [ ] 隐私政策、用户协议

---

*更新时间: 2026-03-15*
