import { Router } from 'express';
import { body } from 'express-validator';
import { validate } from '../middleware/validate.js';
import { AppError } from '../middleware/error.js';
import { PrismaClient } from '@prisma/client';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { logger } from '../utils/logger.js';

const router = Router();
const prisma = new PrismaClient();

const JWT_SECRET = process.env.JWT_SECRET || 'deepmusic-dev-secret';
const JWT_EXPIRES_IN = '7d';

// Token 黑名单 (内存版，生产环境应使用 Redis)
const tokenBlacklist = new Set<string>();

interface JwtPayload {
  userId: string;
  email: string;
}

/// 生成 JWT token
function generateToken(payload: JwtPayload): string {
  return jwt.sign(payload, JWT_SECRET, { expiresIn: JWT_EXPIRES_IN });
}

/// 验证 JWT token 中间件
export function authMiddleware(req: any, res: any, next: any) {
  const authHeader = req.headers.authorization;
  if (!authHeader?.startsWith('Bearer ')) {
    throw new AppError('未授权访问', 401);
  }

  const token = authHeader.substring(7);

  // 检查黑名单
  if (tokenBlacklist.has(token)) {
    throw new AppError('Token 已失效', 401);
  }

  try {
    const decoded = jwt.verify(token, JWT_SECRET) as JwtPayload;
    req.userId = decoded.userId;
    req.userEmail = decoded.email;
    req.token = token;
    next();
  } catch (error) {
    throw new AppError('Token 无效或已过期', 401);
  }
}

// POST /api/auth/register - 注册
router.post(
  '/register',
  body('email').isEmail().withMessage('请输入有效的邮箱'),
  body('password').isLength({ min: 6 }).withMessage('密码至少 6 位'),
  body('nickname').optional().isLength({ min: 1, max: 50 }),
  validate,
  async (req, res, next) => {
    try {
      const { email, password, nickname } = req.body;

      // 检查邮箱是否已注册
      const existing = await prisma.user.findUnique({ where: { email } });
      if (existing) {
        throw new AppError('该邮箱已注册', 409);
      }

      // 加密密码
      const hashedPassword = await bcrypt.hash(password, 12);

      // 创建用户
      const user = await prisma.user.create({
        data: {
          email,
          password: hashedPassword,
          nickname: nickname || email.split('@')[0],
        },
      });

      const token = generateToken({ userId: user.id, email: user.email });

      logger.info(`User registered: ${email}`);

      res.status(201).json({
        success: true,
        data: {
          user: {
            id: user.id,
            email: user.email,
            nickname: user.nickname,
            createdAt: user.createdAt,
          },
          token,
        },
      });
    } catch (error) {
      next(error);
    }
  }
);

// POST /api/auth/login - 登录
router.post(
  '/login',
  body('email').isEmail().withMessage('请输入有效的邮箱'),
  body('password').notEmpty().withMessage('请输入密码'),
  validate,
  async (req, res, next) => {
    try {
      const { email, password } = req.body;

      // 查找用户
      const user = await prisma.user.findUnique({ where: { email } });
      if (!user) {
        throw new AppError('邮箱或密码错误', 401);
      }

      // 验证密码
      const isValid = await bcrypt.compare(password, user.password);
      if (!isValid) {
        throw new AppError('邮箱或密码错误', 401);
      }

      const token = generateToken({ userId: user.id, email: user.email });

      logger.info(`User logged in: ${email}`);

      res.json({
        success: true,
        data: {
          user: {
            id: user.id,
            email: user.email,
            nickname: user.nickname,
            totalPracticeTime: user.totalPracticeTime,
            totalSessions: user.totalSessions,
            totalNotes: user.totalNotes,
            createdAt: user.createdAt,
          },
          token,
        },
      });
    } catch (error) {
      next(error);
    }
  }
);

// POST /api/auth/logout - 登出
router.post('/logout', authMiddleware, async (req: any, res, next) => {
  try {
    // 将 token 加入黑名单
    tokenBlacklist.add(req.token);
    logger.info(`User logged out: ${req.userEmail}`);
    res.json({ success: true, message: '已登出' });
  } catch (error) {
    next(error);
  }
});

// GET /api/auth/me - 获取当前用户信息
router.get('/me', authMiddleware, async (req: any, res, next) => {
  try {
    const user = await prisma.user.findUnique({
      where: { id: req.userId },
      select: {
        id: true,
        email: true,
        nickname: true,
        avatar: true,
        totalPracticeTime: true,
        totalSessions: true,
        totalNotes: true,
        createdAt: true,
        updatedAt: true,
        _count: {
          select: {
            practiceRecords: true,
            favorites: true,
          },
        },
      },
    });

    if (!user) {
      throw new AppError('用户不存在', 404);
    }

    res.json({ success: true, data: user });
  } catch (error) {
    next(error);
  }
});

// PATCH /api/auth/me - 更新用户信息
router.patch(
  '/me',
  authMiddleware,
  body('nickname').optional().isLength({ min: 1, max: 50 }),
  body('avatar').optional().isURL(),
  validate,
  async (req: any, res, next) => {
    try {
      const { nickname, avatar } = req.body;
      const updateData: any = {};
      if (nickname !== undefined) updateData.nickname = nickname;
      if (avatar !== undefined) updateData.avatar = avatar;

      const user = await prisma.user.update({
        where: { id: req.userId },
        data: updateData,
        select: {
          id: true,
          email: true,
          nickname: true,
          avatar: true,
          updatedAt: true,
        },
      });

      res.json({ success: true, data: user });
    } catch (error) {
      next(error);
    }
  }
);

export default router;
