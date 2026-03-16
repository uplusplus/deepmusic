# DeepMusic Server

DeepMusic 后端 API 服务

## 技术栈

- Node.js 18+
- TypeScript
- Express
- Prisma (ORM)
- PostgreSQL
- Redis

## 快速开始

### 1. 安装依赖

```bash
npm install
```

### 2. 配置环境变量

```bash
cp .env.example .env
# 编辑 .env 文件，配置数据库连接
```

### 3. 初始化数据库

```bash
# 生成 Prisma Client
npm run db:generate

# 运行数据库迁移
npm run db:migrate

# 填充初始数据
npm run db:seed
```

### 4. 导入乐谱数据

```bash
npm run scores:import
```

### 5. 启动开发服务器

```bash
npm run dev
```

## API 文档

### 健康检查

```
GET /health
```

### 乐谱 API

```
GET    /api/scores           # 获取乐谱列表
GET    /api/scores/recommended  # 获取推荐乐谱
GET    /api/scores/search    # 搜索乐谱
GET    /api/scores/:id       # 获取单个乐谱
POST   /api/scores           # 上传乐谱
PATCH  /api/scores/:id       # 更新乐谱
DELETE /api/scores/:id       # 删除乐谱
POST   /api/scores/:id/publish # 发布乐谱
```

### 查询参数

```
GET /api/scores?page=1&limit=20&difficulty=BEGINNER&category=古典&search=贝多芬
```

## 项目结构

```
server/
├── prisma/
│   └── schema.prisma      # 数据库模型
├── src/
│   ├── index.ts           # 入口文件
│   ├── routes/            # 路由
│   ├── services/          # 业务逻辑
│   ├── middleware/        # 中间件
│   ├── utils/             # 工具函数
│   └── scripts/           # 脚本
├── uploads/               # 上传文件
├── logs/                  # 日志文件
└── package.json
```

## 部署

### 本地开发

```bash
npm run dev
```

### 生产环境

```bash
npm run build
npm start
```

### Docker (可选)

```bash
docker build -t deepmusic-server .
docker run -p 3000:3000 deepmusic-server
```

## 环境要求

- PostgreSQL 14+
- Redis 6+
- Node.js 18+
