# DeepMusic - 开发环境配置指南

> 版本: 1.1 | 更新: 2026-03-20

---

## 1. 环境要求

### 必需

| 工具 | 版本要求 | 说明 |
|------|----------|------|
| Node.js | >= 18.0.0 | 后端运行时 |
| npm | >= 9.0 | 包管理 |
| Flutter SDK | >= 3.0.0 | 移动端开发 |
| Git | 任意 | 版本控制 |

### 按需安装

| 工具 | 版本要求 | 用途 |
|------|----------|------|
| Android Studio | 最新 | Android 开发 + 模拟器 |
| Xcode | 14+ | iOS 开发（仅 macOS） |
| VS Code | 最新 | 推荐 IDE |

---

## 2. 后端环境 (server/)

### 2.1 安装依赖

```bash
cd server
npm install
```

### 2.2 环境变量

```bash
cp .env.example .env
```

`.env` 配置项：

```env
# 服务端口
PORT=3000

# 数据库 (开发用 SQLite，生产用 PostgreSQL)
DATABASE_URL="file:./dev.db"
# 生产环境示例:
# DATABASE_URL="postgresql://user:pass@localhost:5432/deepmusic"

# JWT 密钥
JWT_SECRET="your-secret-key-here"

# 文件上传目录
UPLOAD_DIR="./uploads/scores"

# CORS
CORS_ORIGIN="*"

# Redis (可选，Phase 2 启用)
REDIS_URL="redis://localhost:6379"
```

### 2.3 数据库初始化

```bash
# 生成 Prisma Client
npm run db:generate

# 运行迁移 (创建表)
npm run db:migrate

# 导入种子数据 (用户数据)
npm run db:seed

# 导入乐谱数据
npm run scores:import
```

### 2.4 启动开发服务器

```bash
npm run dev
# 输出: 🚀 DeepMusic Server running on port 3000
# 健康检查: http://localhost:3000/health
# API 基础路径: http://localhost:3000/api
```

### 2.5 生产构建

```bash
npm run build    # TypeScript 编译
npm start        # 启动编译后的 JS
```

---

## 3. 移动端环境 (mobile/)

### 3.1 安装 Flutter

#### Linux

```bash
# 下载 Flutter SDK
cd ~/tools
git clone https://github.com/flutter/flutter.git -b stable

# 添加到 PATH
echo 'export PATH="$HOME/tools/flutter/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc

# 验证
flutter doctor
```

#### Windows

```powershell
# 下载 ZIP: https://docs.flutter.dev/get-started/install/windows
# 解压到 C:\tools\flutter

# 添加到环境变量
[Environment]::SetEnvironmentVariable("Path", $env:Path + ";C:\tools\flutter\bin", "User")
```

#### macOS

```bash
# 使用 Homebrew
brew install --cask flutter

# 验证
flutter doctor
```

### 3.2 Android 开发环境

1. 安装 [Android Studio](https://developer.android.com/studio)
2. 打开 SDK Manager，安装：
   - Android SDK (最新稳定版)
   - Android SDK Build-Tools
   - Android SDK Platform-Tools
3. 创建 Android 模拟器 (AVD) 或连接真机

```bash
# 验证 Android 环境
flutter doctor
# 确保 "Android toolchain" 显示 ✓
```

### 3.3 iOS 开发环境 (仅 macOS)

1. 安装 Xcode (App Store)
2. 安装 Xcode Command Line Tools:
   ```bash
   xcode-select --install
   ```
3. 同意 Xcode 许可:
   ```bash
   sudo xcodebuild -license accept
   ```

### 3.4 安装 Flutter 依赖

```bash
cd mobile
flutter pub get
```

### 3.5 运行应用

```bash
# 查看可用设备
flutter devices

# Android 模拟器
flutter run

# 指定设备
flutter run -d <device-id>

# 构建 APK
flutter build apk

# 构建 iOS (需 macOS)
flutter build ios
```

---

## 4. IDE 配置

### VS Code (推荐)

**必装扩展**:
- [Flutter](https://marketplace.visualstudio.com/items?itemName=Dart-Code.flutter)
- [Dart](https://marketplace.visualstudio.com/items?itemName=Dart-Code.dart-code)

**推荐扩展**:
- Error Lens
- GitLens
- ESLint (后端 TypeScript)
- Prisma (Prisma schema 支持)

**`.vscode/settings.json`**:
```json
{
  "dart.flutterSdkPath": "~/tools/flutter",
  "editor.formatOnSave": true,
  "[dart]": {
    "editor.defaultFormatter": "Dart-Code.dart-code"
  }
}
```

### Android Studio

1. 安装 Flutter 和 Dart 插件 (Settings → Plugins)
2. 配置 Flutter SDK 路径
3. 打开 `mobile/` 作为 Flutter 项目

---

## 5. 蓝牙 MIDI 测试环境

### 所需硬件

- **数字钢琴**: Yamaha P125 (或支持 BLE MIDI 的设备)
- **测试手机**: 支持蓝牙 4.0+ BLE 的 Android / iOS 设备

### Android 配置

1. 在系统设置中启用蓝牙
2. 打开 Yamaha P125 的蓝牙功能
3. 在 App 中扫描并连接

**权限要求** (自动处理):
- `BLUETOOTH_SCAN`
- `BLUETOOTH_CONNECT`
- `ACCESS_FINE_LOCATION` (Android 11 及以下)

### iOS 配置

1. 系统设置中允许 App 使用蓝牙
2. App 会自动扫描 BLE MIDI 设备

**Info.plist 配置** (已由 `flutter_midi_command` 自动处理):
- `NSBluetoothAlwaysUsageDescription`
- `NSBluetoothPeripheralUsageDescription`

---

## 6. API 测试

### 使用 curl

```bash
# 健康检查
curl http://localhost:3000/health

# 注册用户
curl -X POST http://localhost:3000/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"123456","nickname":"测试用户"}'

# 登录
curl -X POST http://localhost:3000/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"123456"}'

# 获取乐谱列表
curl http://localhost:3000/api/scores

# 获取乐谱详情
curl http://localhost:3000/api/scores/<score-id>
```

---

## 7. 常见问题

### Q: `flutter doctor` 显示 Android toolchain 问题
A: 运行 `flutter doctor --android-licenses` 接受所有许可协议。

### Q: `prisma generate` 失败
A: 确保 Node.js >= 18，删除 `node_modules` 重新 `npm install`。

### Q: Android 模拟器蓝牙不可用
A: Android 模拟器**不支持蓝牙**。蓝牙 MIDI 测试必须使用**真机**。

### Q: iOS 构建失败 (Windows/Linux)
A: iOS 构建必须在 macOS 上进行，或使用云构建服务 (Codemagic / Bitrise)。

### Q: MusicXML 文件无法渲染
A: 检查文件编码是否为 UTF-8，确保 XML 结构符合 MusicXML 3.1 规范。

---

## 8. 项目文件结构 (当前实际)

```
deepmusic/
├── README.md
├── docs/
│   ├── PRD.md              # 产品需求文档
│   ├── ARCHITECTURE.md     # 技术架构文档
│   ├── ROADMAP.md          # 开发路线图
│   └── SETUP.md            # 本文件
├── mobile/                 # Flutter 移动端
│   ├── lib/
│   │   ├── core/           # 核心基础设施
│   │   ├── features/       # 功能模块
│   │   ├── shared/         # 共享组件
│   │   └── data/           # 数据层
│   ├── assets/
│   └── pubspec.yaml
├── server/                 # Express 后端
│   ├── src/
│   │   ├── routes/         # API 路由
│   │   ├── services/       # 业务逻辑
│   │   ├── middleware/      # 中间件
│   │   └── utils/          # 工具函数
│   ├── prisma/
│   │   ├── schema.prisma   # 数据模型
│   │   └── dev.db          # SQLite 开发库
│   └── package.json
└── .git/
```

---

*配置指南维护: 项目团队 | 更新: 2026-03-20*
