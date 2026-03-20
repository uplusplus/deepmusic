import { Router } from 'express';
import { body, query, param } from 'express-validator';
import { validate } from '../middleware/validate.js';
import { AppError } from '../middleware/error.js';
import { PrismaClient } from '@prisma/client';
import { authMiddleware } from './auth.js';
import { logger } from '../utils/logger.js';

const router = Router();
const prisma = new PrismaClient();

// 所有 user 路由都需要认证
router.use(authMiddleware);

// GET /api/user/profile - 获取个人资料
router.get('/profile', async (req: any, res, next) => {
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

// PUT /api/user/profile - 更新个人资料
router.put(
  '/profile',
  body('nickname').optional().isLength({ min: 1, max: 50 }).withMessage('昵称长度 1-50'),
  body('avatar').optional().isURL().withMessage('头像需为有效 URL'),
  validate,
  async (req: any, res, next) => {
    try {
      const { nickname, avatar } = req.body;
      const updateData: Record<string, any> = {};
      if (nickname !== undefined) updateData.nickname = nickname;
      if (avatar !== undefined) updateData.avatar = avatar;

      if (Object.keys(updateData).length === 0) {
        throw new AppError('请提供要更新的字段', 400);
      }

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

      logger.info(`User profile updated: ${req.userId}`);
      res.json({ success: true, data: user });
    } catch (error) {
      next(error);
    }
  }
);

// GET /api/user/favorites - 获取收藏列表
router.get(
  '/favorites',
  query('page').optional().isInt({ min: 1 }),
  query('limit').optional().isInt({ min: 1, max: 100 }),
  validate,
  async (req: any, res, next) => {
    try {
      const page = parseInt(req.query.page as string) || 1;
      const limit = parseInt(req.query.limit as string) || 20;
      const skip = (page - 1) * limit;

      const user = await prisma.user.findUnique({
        where: { id: req.userId },
        include: {
          favorites: {
            skip,
            take: limit,
            orderBy: { createdAt: 'desc' },
            include: { tags: true },
          },
        },
      });

      if (!user) {
        throw new AppError('用户不存在', 404);
      }

      const total = await prisma.user
        .findUnique({ where: { id: req.userId } })
        .favorites();

      res.json({
        success: true,
        data: user.favorites,
        pagination: {
          page,
          limit,
          total: total?.length ?? 0,
          totalPages: Math.ceil((total?.length ?? 0) / limit),
        },
      });
    } catch (error) {
      next(error);
    }
  }
);

// GET /api/user/statistics - 获取统计数据
router.get('/statistics', async (req: any, res, next) => {
  try {
    const userId = req.userId;
    const period = (req.query.period as string) || 'all';

    // 用户基础统计
    const user = await prisma.user.findUnique({
      where: { id: userId },
      select: {
        totalPracticeTime: true,
        totalSessions: true,
        totalNotes: true,
      },
    });

    if (!user) {
      throw new AppError('用户不存在', 404);
    }

    // 计算时间范围
    let dateFilter: Date | undefined;
    if (period === 'week') {
      dateFilter = new Date();
      dateFilter.setDate(dateFilter.getDate() - 7);
    } else if (period === 'month') {
      dateFilter = new Date();
      dateFilter.setMonth(dateFilter.getMonth() - 1);
    }

    const whereCondition: any = { userId };
    if (dateFilter) {
      whereCondition.completedAt = { gte: dateFilter };
    }

    // 区间内记录
    const records = await prisma.practiceRecord.findMany({
      where: whereCondition,
      select: {
        duration: true,
        notesPlayed: true,
        overallScore: true,
        pitchScore: true,
        rhythmScore: true,
        grade: true,
        completedAt: true,
        score: {
          select: { id: true, title: true, composer: true },
        },
      },
      orderBy: { completedAt: 'desc' },
    });

    const periodSessions = records.length;
    const periodDuration = records.reduce((sum, r) => sum + r.duration, 0);
    const periodNotes = records.reduce((sum, r) => sum + r.notesPlayed, 0);
    const avgScore =
      records.length > 0
        ? records.reduce((sum, r) => sum + r.overallScore, 0) / records.length
        : 0;
    const avgPitch =
      records.length > 0
        ? records.reduce((sum, r) => sum + r.pitchScore, 0) / records.length
        : 0;
    const avgRhythm =
      records.length > 0
        ? records.reduce((sum, r) => sum + r.rhythmScore, 0) / records.length
        : 0;

    // 等级分布
    const gradeDistribution: Record<string, number> = {};
    for (const r of records) {
      gradeDistribution[r.grade] = (gradeDistribution[r.grade] || 0) + 1;
    }

    // 最佳成绩 (按乐谱分组取最高分)
    const bestByScore = new Map<
      string,
      { scoreId: string; title: string; composer: string; bestScore: number }
    >();
    for (const r of records) {
      const existing = bestByScore.get(r.score.id);
      if (!existing || r.overallScore > existing.bestScore) {
        bestByScore.set(r.score.id, {
          scoreId: r.score.id,
          title: r.score.title,
          composer: r.score.composer,
          bestScore: r.overallScore,
        });
      }
    }
    const topScores = Array.from(bestByScore.values())
      .sort((a, b) => b.bestScore - a.bestScore)
      .slice(0, 5);

    // 按天统计 (最近 7 天或区间内)
    const dailyStats: Record<
      string,
      { sessions: number; duration: number; avgScore: number }
    > = {};
    for (const r of records) {
      const day = r.completedAt.toISOString().split('T')[0];
      if (!dailyStats[day]) {
        dailyStats[day] = { sessions: 0, duration: 0, avgScore: 0 };
      }
      dailyStats[day].sessions++;
      dailyStats[day].duration += r.duration;
    }
    for (const day of Object.keys(dailyStats)) {
      const dayRecords = records.filter(
        (r) => r.completedAt.toISOString().split('T')[0] === day
      );
      dailyStats[day].avgScore =
        dayRecords.reduce((sum, r) => sum + r.overallScore, 0) /
        dayRecords.length;
    }

    res.json({
      success: true,
      data: {
        period,
        summary: {
          totalPracticeTime: user.totalPracticeTime,
          totalSessions: user.totalSessions,
          totalNotes: user.totalNotes,
          periodSessions,
          periodDuration,
          periodNotes,
        },
        averages: {
          overallScore: Math.round(avgScore * 100) / 100,
          pitchScore: Math.round(avgPitch * 100) / 100,
          rhythmScore: Math.round(avgRhythm * 100) / 100,
        },
        gradeDistribution,
        topScores,
        dailyStats,
      },
    });
  } catch (error) {
    next(error);
  }
});

export default router;
