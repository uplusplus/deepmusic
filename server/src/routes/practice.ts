import { Router } from 'express';
import { body, query, param } from 'express-validator';
import { validate } from '../middleware/validate.js';
import { AppError } from '../middleware/error.js';
import { PrismaClient } from '@prisma/client';
import { logger } from '../utils/logger.js';

const router = Router();
const prisma = new PrismaClient();

// POST /api/practice - 创建练习记录
router.post(
  '/',
  body('scoreId').isUUID().withMessage('无效的乐谱 ID'),
  body('duration').isInt({ min: 1 }).withMessage('练习时长必须为正整数'),
  body('notesPlayed').isInt({ min: 0 }).withMessage('音符数量无效'),
  body('pitchScore').isFloat({ min: 0, max: 100 }).withMessage('音准分数范围 0-100'),
  body('rhythmScore').isFloat({ min: 0, max: 100 }).withMessage('节奏分数范围 0-100'),
  body('overallScore').isFloat({ min: 0, max: 100 }).withMessage('综合分数范围 0-100'),
  body('grade').isIn(['S', 'A', 'B', 'C', 'D', 'F']).withMessage('等级无效'),
  body('details').optional().isString(),
  body('startedAt').isISO8601().withMessage('开始时间格式无效'),
  validate,
  async (req: any, res, next) => {
    try {
      const {
        scoreId,
        duration,
        notesPlayed,
        pitchScore,
        rhythmScore,
        overallScore,
        grade,
        details,
        startedAt,
      } = req.body;

      // 验证乐谱存在
      const score = await prisma.score.findUnique({ where: { id: scoreId } });
      if (!score) {
        throw new AppError('乐谱不存在', 404);
      }

      // 创建练习记录
      const record = await prisma.practiceRecord.create({
        data: {
          userId: req.userId,
          scoreId,
          duration,
          notesPlayed,
          pitchScore,
          rhythmScore,
          overallScore,
          grade,
          details: details || null,
          startedAt: new Date(startedAt),
        },
      });

      // 更新乐谱播放统计
      await prisma.score.update({
        where: { id: scoreId },
        data: { playCount: { increment: 1 } },
      });

      // 更新用户统计
      await prisma.user.update({
        where: { id: req.userId },
        data: {
          totalPracticeTime: { increment: duration },
          totalSessions: { increment: 1 },
          totalNotes: { increment: notesPlayed },
        },
      });

      logger.info(`Practice record created: ${record.id} by user ${req.userId}`);

      res.status(201).json({
        success: true,
        data: record,
      });
    } catch (error) {
      next(error);
    }
  }
);

// GET /api/practice - 获取练习历史
router.get(
  '/',
  query('page').optional().isInt({ min: 1 }),
  query('limit').optional().isInt({ min: 1, max: 100 }),
  query('scoreId').optional().isUUID(),
  validate,
  async (req: any, res, next) => {
    try {
      const page = parseInt(req.query.page as string) || 1;
      const limit = parseInt(req.query.limit as string) || 20;
      const scoreId = req.query.scoreId as string;
      const skip = (page - 1) * limit;

      const where: any = { userId: req.userId };
      if (scoreId) where.scoreId = scoreId;

      const [records, total] = await Promise.all([
        prisma.practiceRecord.findMany({
          where,
          skip,
          take: limit,
          orderBy: { completedAt: 'desc' },
          include: {
            score: {
              select: {
                id: true,
                title: true,
                composer: true,
                difficulty: true,
              },
            },
          },
        }),
        prisma.practiceRecord.count({ where }),
      ]);

      res.json({
        success: true,
        data: records,
        pagination: {
          page,
          limit,
          total,
          totalPages: Math.ceil(total / limit),
        },
      });
    } catch (error) {
      next(error);
    }
  }
);

// GET /api/practice/stats - 获取统计数据
router.get('/stats', async (req: any, res, next) => {
  try {
    const userId = req.userId;

    // 基础统计
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

    // 最高分
    const bestScores = await prisma.practiceRecord.groupBy({
      by: ['scoreId'],
      where: { userId },
      _max: { overallScore: true },
      orderBy: { _max: { overallScore: 'desc' } },
      take: 5,
    });

    // 获取这些乐谱的标题
    const scoreIds = bestScores.map((s) => s.scoreId);
    const scores = await prisma.score.findMany({
      where: { id: { in: scoreIds } },
      select: { id: true, title: true, composer: true },
    });

    const scoreMap = Object.fromEntries(scores.map((s) => [s.id, s]));

    const topScores = bestScores.map((bs) => ({
      ...scoreMap[bs.scoreId],
      bestScore: bs._max.overallScore,
    }));

    // 最近 7 天的练习统计
    const sevenDaysAgo = new Date();
    sevenDaysAgo.setDate(sevenDaysAgo.getDate() - 7);

    const recentRecords = await prisma.practiceRecord.findMany({
      where: {
        userId,
        completedAt: { gte: sevenDaysAgo },
      },
      select: {
        completedAt: true,
        duration: true,
        overallScore: true,
      },
    });

    // 按天分组
    const dailyStats: Record<string, { sessions: number; duration: number; avgScore: number }> = {};
    for (const record of recentRecords) {
      const day = record.completedAt.toISOString().split('T')[0];
      if (!dailyStats[day]) {
        dailyStats[day] = { sessions: 0, duration: 0, avgScore: 0 };
      }
      dailyStats[day].sessions++;
      dailyStats[day].duration += record.duration;
    }

    // 计算每天的平均分
    for (const day of Object.keys(dailyStats)) {
      const dayRecords = recentRecords.filter(
        (r) => r.completedAt.toISOString().split('T')[0] === day
      );
      dailyStats[day].avgScore =
        dayRecords.reduce((sum, r) => sum + r.overallScore, 0) / dayRecords.length;
    }

    // 等级分布
    const gradeDistribution = await prisma.practiceRecord.groupBy({
      by: ['grade'],
      where: { userId },
      _count: true,
    });

    res.json({
      success: true,
      data: {
        summary: {
          totalPracticeTime: user.totalPracticeTime,
          totalSessions: user.totalSessions,
          totalNotes: user.totalNotes,
        },
        topScores,
        dailyStats,
        gradeDistribution: Object.fromEntries(
          gradeDistribution.map((g) => [g.grade, g._count])
        ),
      },
    });
  } catch (error) {
    next(error);
  }
});

// GET /api/practice/:id - 获取单条练习记录详情
router.get(
  '/:id',
  param('id').isUUID(),
  validate,
  async (req: any, res, next) => {
    try {
      const record = await prisma.practiceRecord.findFirst({
        where: {
          id: req.params.id,
          userId: req.userId,
        },
        include: {
          score: {
            select: {
              id: true,
              title: true,
              composer: true,
              difficulty: true,
              category: true,
            },
          },
        },
      });

      if (!record) {
        throw new AppError('练习记录不存在', 404);
      }

      res.json({ success: true, data: record });
    } catch (error) {
      next(error);
    }
  }
);

// DELETE /api/practice/:id - 删除练习记录
router.delete(
  '/:id',
  param('id').isUUID(),
  validate,
  async (req: any, res, next) => {
    try {
      const record = await prisma.practiceRecord.findFirst({
        where: {
          id: req.params.id,
          userId: req.userId,
        },
      });

      if (!record) {
        throw new AppError('练习记录不存在', 404);
      }

      await prisma.practiceRecord.delete({
        where: { id: req.params.id },
      });

      // 更新用户统计
      await prisma.user.update({
        where: { id: req.userId },
        data: {
          totalPracticeTime: { decrement: record.duration },
          totalSessions: { decrement: 1 },
          totalNotes: { decrement: record.notesPlayed },
        },
      });

      logger.info(`Practice record deleted: ${req.params.id}`);
      res.json({ success: true, message: '记录已删除' });
    } catch (error) {
      next(error);
    }
  }
);

export default router;
