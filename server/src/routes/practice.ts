import { Router } from 'express';
import { body, query, param } from 'express-validator';
import { validate } from '../middleware/validate.js';
import { AppError } from '../middleware/error.js';
import { authMiddleware } from './auth.js';
import { PrismaClient } from '@prisma/client';
import { logger } from '../utils/logger.js';

const router = Router();
const prisma = new PrismaClient();

// 所有 practice 路由都需要认证
router.use(authMiddleware);

// ============================================================
// POST /api/practice/start - 开始练习会话
// ============================================================
router.post(
  '/start',
  body('scoreId').isUUID().withMessage('无效的乐谱 ID'),
  validate,
  async (req: any, res, next) => {
    try {
      const { scoreId } = req.body;

      // 验证乐谱存在且已发布
      const score = await prisma.score.findFirst({
        where: { id: scoreId, status: 'PUBLISHED', isPublic: true },
      });
      if (!score) {
        throw new AppError('乐谱不存在或未发布', 404);
      }

      // 检查是否有活跃会话
      const existingSession = await prisma.practiceSession.findFirst({
        where: { userId: req.userId, status: 'ACTIVE' },
      });
      if (existingSession) {
        // 自动放弃旧会话
        await prisma.practiceSession.update({
          where: { id: existingSession.id },
          data: { status: 'ABANDONED', updatedAt: new Date() },
        });
        logger.info(`Auto-abandoned stale session: ${existingSession.id}`);
      }

      // 创建持久化会话
      const session = await prisma.practiceSession.create({
        data: {
          userId: req.userId,
          scoreId,
          startedAt: new Date(),
          status: 'ACTIVE',
          noteEvents: '[]',
        },
      });

      logger.info(
        `Practice session started: ${session.id} (user=${req.userId}, score=${scoreId})`
      );

      res.status(201).json({
        success: true,
        data: {
          sessionId: session.id,
          scoreId,
          score: {
            id: score.id,
            title: score.title,
            composer: score.composer,
            difficulty: score.difficulty,
            tempo: score.tempo,
            timeSignature: score.timeSignature,
            keySignature: score.keySignature,
            measures: score.measures,
          },
          startedAt: session.startedAt.toISOString(),
        },
      });
    } catch (error) {
      next(error);
    }
  }
);

// ============================================================
// POST /api/practice/:id/note - 上传音符事件
// ============================================================
router.post(
  '/:id/note',
  param('id').isUUID(),
  body('notes').isArray({ min: 1, max: 500 }).withMessage('notes 必须为数组 (1-500)'),
  body('notes.*.noteNumber').isInt({ min: 0, max: 127 }),
  body('notes.*.velocity').isInt({ min: 0, max: 127 }),
  body('notes.*.type').isIn(['noteOn', 'noteOff']),
  body('notes.*.timestamp').isISO8601(),
  validate,
  async (req: any, res, next) => {
    try {
      const sessionId = req.params.id;

      // 从数据库读取会话
      const session = await prisma.practiceSession.findUnique({
        where: { id: sessionId },
      });

      if (!session || session.status !== 'ACTIVE') {
        throw new AppError('练习会话不存在或已结束', 404);
      }

      if (session.userId !== req.userId) {
        throw new AppError('无权访问此练习会话', 403);
      }

      const { notes } = req.body;

      // 追加音符事件 (读取 → 合并 → 写回)
      const existing = JSON.parse(session.noteEvents || '[]');
      const merged = [...existing, ...notes];

      // 截断: 最多保留 5000 条事件防止膨胀
      const trimmed = merged.length > 5000
        ? merged.slice(merged.length - 5000)
        : merged;

      await prisma.practiceSession.update({
        where: { id: sessionId },
        data: {
          noteEvents: JSON.stringify(trimmed),
          updatedAt: new Date(),
        },
      });

      res.json({
        success: true,
        data: {
          accepted: notes.length,
          totalEvents: trimmed.length,
        },
      });
    } catch (error) {
      next(error);
    }
  }
);

// ============================================================
// POST /api/practice/:id/end - 结束练习并提交报告
// ============================================================
router.post(
  '/:id/end',
  param('id').isUUID(),
  body('duration').isInt({ min: 1 }).withMessage('练习时长必须为正整数 (秒)'),
  body('notesPlayed').isInt({ min: 0 }).withMessage('音符数量无效'),
  body('pitchScore').isFloat({ min: 0, max: 100 }).withMessage('音准分数范围 0-100'),
  body('rhythmScore').isFloat({ min: 0, max: 100 }).withMessage('节奏分数范围 0-100'),
  body('overallScore').isFloat({ min: 0, max: 100 }).withMessage('综合分数范围 0-100'),
  body('grade').isIn(['S', 'A', 'B', 'C', 'D', 'F']).withMessage('等级无效'),
  body('details').optional().isString(),
  validate,
  async (req: any, res, next) => {
    try {
      const sessionId = req.params.id;

      const session = await prisma.practiceSession.findUnique({
        where: { id: sessionId },
      });

      if (!session || session.status !== 'ACTIVE') {
        throw new AppError('练习会话不存在或已结束', 404);
      }

      if (session.userId !== req.userId) {
        throw new AppError('无权访问此练习会话', 403);
      }

      const {
        duration,
        notesPlayed,
        pitchScore,
        rhythmScore,
        overallScore,
        grade,
        details,
      } = req.body;

      // 事务: 创建记录 + 更新统计 + 标记会话完成
      const result = await prisma.$transaction(async (tx) => {
        // 创建练习记录
        const record = await tx.practiceRecord.create({
          data: {
            user: { connect: { id: req.userId } },
            score: { connect: { id: session.scoreId } },
            duration,
            notesPlayed,
            pitchScore,
            rhythmScore,
            overallScore,
            grade,
            details: details
              ? details
              : JSON.stringify({
                  noteEventsCount: JSON.parse(session.noteEvents || '[]').length,
                }),
            startedAt: session.startedAt,
          },
        });

        // 更新乐谱播放统计
        await tx.score.update({
          where: { id: session.scoreId },
          data: { playCount: { increment: 1 } },
        });

        // 更新用户统计
        await tx.user.update({
          where: { id: req.userId },
          data: {
            totalPracticeTime: { increment: duration },
            totalSessions: { increment: 1 },
            totalNotes: { increment: notesPlayed },
          },
        });

        // 标记会话完成
        await tx.practiceSession.update({
          where: { id: sessionId },
          data: {
            status: 'COMPLETED',
            updatedAt: new Date(),
          },
        });

        return record;
      });

      logger.info(
        `Practice session ended: ${sessionId} → record ${result.id} (grade=${grade}, score=${overallScore})`
      );

      res.json({
        success: true,
        data: result,
      });
    } catch (error) {
      next(error);
    }
  }
);

// ============================================================
// POST /api/practice - 直接创建练习记录 (一次性提交)
// ============================================================
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

      const score = await prisma.score.findUnique({ where: { id: scoreId } });
      if (!score) {
        throw new AppError('乐谱不存在', 404);
      }

      const result = await prisma.$transaction(async (tx) => {
        const record = await tx.practiceRecord.create({
          data: {
            user: { connect: { id: req.userId } },
            score: { connect: { id: scoreId } },
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

        await tx.score.update({
          where: { id: scoreId },
          data: { playCount: { increment: 1 } },
        });

        await tx.user.update({
          where: { id: req.userId },
          data: {
            totalPracticeTime: { increment: duration },
            totalSessions: { increment: 1 },
            totalNotes: { increment: notesPlayed },
          },
        });

        return record;
      });

      logger.info(`Practice record created: ${result.id} by user ${req.userId}`);
      res.status(201).json({ success: true, data: result });
    } catch (error) {
      next(error);
    }
  }
);

// ============================================================
// GET /api/practice - 练习历史
// ============================================================
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

// ============================================================
// GET /api/practice/stats - 统计数据
// ============================================================
router.get('/stats', async (req: any, res, next) => {
  try {
    const userId = req.userId;

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

    // 最近 7 天
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

    const dailyStats: Record<
      string,
      { sessions: number; duration: number; avgScore: number }
    > = {};
    for (const record of recentRecords) {
      const day = record.completedAt.toISOString().split('T')[0];
      if (!dailyStats[day]) {
        dailyStats[day] = { sessions: 0, duration: 0, avgScore: 0 };
      }
      dailyStats[day].sessions++;
      dailyStats[day].duration += record.duration;
    }

    for (const day of Object.keys(dailyStats)) {
      const dayRecords = recentRecords.filter(
        (r) => r.completedAt.toISOString().split('T')[0] === day
      );
      dailyStats[day].avgScore =
        dayRecords.reduce((sum, r) => sum + r.overallScore, 0) /
        dayRecords.length;
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

// ============================================================
// GET /api/practice/:id - 单条记录详情
// ============================================================
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

// ============================================================
// DELETE /api/practice/:id - 删除练习记录
// ============================================================
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

      await prisma.$transaction(async (tx) => {
        await tx.practiceRecord.delete({
          where: { id: req.params.id },
        });

        await tx.user.update({
          where: { id: req.userId },
          data: {
            totalPracticeTime: { decrement: record.duration },
            totalSessions: { decrement: 1 },
            totalNotes: { decrement: record.notesPlayed },
          },
        });
      });

      logger.info(`Practice record deleted: ${req.params.id}`);
      res.json({ success: true, message: '记录已删除' });
    } catch (error) {
      next(error);
    }
  }
);

export default router;
