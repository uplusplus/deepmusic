# DeepMusic - Development Setup Guide

## 环境检查

| 工具 | 状态 | 版本 |
|------|------|------|
| Node.js | ✅ 已安装 | v24.14.0 |
| Python | ✅ 已安装 | 3.9.2 |
| Git | ✅ 已安装 | 2.37.2.windows.2 |
| Flutter | ❌ 未安装 | - |
| Android Studio | ❓ 待确认 | - |
| Xcode | ❌ N/A (Windows) | - |

---

## Flutter 安装步骤

### 1. 下载 Flutter SDK

```powershell
# 方式一：使用 Git
cd C:\tools
git clone https://github.com/flutter/flutter.git -b stable

# 方式二：下载 ZIP
# 访问 https://docs.flutter.dev/get-started/install/windows
# 下载 flutter_windows_x.x.x-stable.zip
```

### 2. 配置环境变量

```powershell
# 添加到 PATH
$env:Path += ";C:\tools\flutter\bin"

# 永久添加 (管理员权限)
[Environment]::SetEnvironmentVariable("Path", $env:Path + ";C:\tools\flutter\bin", "User")
```

### 3. 验证安装

```powershell
flutter doctor
```

### 4. 安装 Android Studio (开发 Android 应用)

1. 下载: https://developer.android.com/studio
2. 安装 Android SDK
3. 配置 Android 模拟器

### 5. iOS 开发 (需要 macOS)

Windows 无法进行 iOS 开发和调试。
解决方案：
- 使用 macOS 设备
- 使用云构建服务 (Codemagic, Bitrise)
- 使用远程 Mac (MacStadium, MacinCloud)

---

## 快速开始 (Flutter 安装后)

```powershell
# 进入项目目录
cd C:\Users\JOY\.openclaw\workspace\DeepMusic\mobile

# 获取依赖
flutter pub get

# 运行应用 (Android 模拟器)
flutter run

# 构建 APK
flutter build apk

# 构建 iOS (需要 macOS)
flutter build ios
```

---

## 项目结构 (预创建)

```
DeepMusic/
├── README.md
├── docs/
│   ├── PRD.md
│   ├── ARCHITECTURE.md
│   ├── SETUP.md          # 本文件
│   └── ROADMAP.md
├── mobile/               # Flutter 项目 (待创建)
│   ├── lib/
│   ├── assets/
│   └── pubspec.yaml
├── server/               # 后端服务 (待创建)
│   ├── src/
│   └── package.json
├── web/                  # Web Admin (待创建)
│   └── ...
└── assets/
    └── scores/           # 曲谱资源
```

---

## 开发工具推荐

### IDE
- **VS Code** + Flutter 扩展 (推荐)
- **Android Studio** + Flutter 插件
- **IntelliJ IDEA** + Flutter 插件

### VS Code 扩展
- Flutter
- Dart
- Awesome Flutter Snippets
- Error Lens
- GitLens

### 设计工具
- **Figma** - UI 设计
- **Adobe XD** - UI 设计

---

## 无版权乐谱资源

### 推荐来源

| 来源 | 说明 | 网址 |
|------|------|------|
| IMSLP | 公有领域古典乐谱 | https://imslp.org |
| Mutopia | 免费乐谱 | https://mutopiaproject.org |
| OpenScore | 公有领域乐谱数字化 | https://musescore.com/openscore |
| Petrucci Music Library | 古典音乐库 | https://imslp.org |

### 一期推荐曲谱 (30首)

**初级练习曲**
1. 拜厄 - 钢琴基础教程选曲
2. 车尔尼 - 初级练习曲 Op.599 选曲
3. 布格缪勒 - 25首简易练习曲 Op.100 选曲

**古典入门**
4. 巴赫 - 小步舞曲 (Minuet in G)
5. 巴赫 - 二部创意曲选曲
6. 莫扎特 - 小星星变奏曲
7. 贝多芬 - 致爱丽丝
8. 舒曼 - 梦幻曲

**流行/轻音乐**
9-15. 待定 (选择无版权流行改编曲)

---

## 下一步

1. [ ] 安装 Flutter SDK
2. [ ] 安装 Android Studio
3. [ ] 运行 `flutter doctor` 检查环境
4. [ ] 初始化 Flutter 项目
5. [ ] 收集 30 首无版权乐谱 (MusicXML 格式)

---

*更新时间: 2026-03-15*
