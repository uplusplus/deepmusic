import { Router } from 'express';
import { body, query, param } from 'express-validator';
import { validate } from '../middleware/validate.js';
import { AppError } from '../middleware/error.js';
import { authMiddleware } from './auth.js';
import * as scoreService from '../services/score.service.js';
import { PrismaClient } from '@prisma/client';
import multer from 'multer';
import path from 'path';
import fs from 'fs';
import { logger } from '../utils/logger.js';

const router = Router();
const prisma = new PrismaClient();

// 配置文件上传
const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    const uploadDir = process.env.UPLOAD_DIR || './uploads/scores';
    if (!fs.existsSync(uploadDir)) {
      fs.mkdirSync(uploadDir, { recursive: true });
    }
    cb(null, uploadDir);
  },
  filename: (req, file, cb) => {
    const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1e9);
    cb(null, uniqueSuffix + path.extname(file.originalname));
  },
});

const upload = multer({
  storage,
  fileFilter: (req, file, cb) => {
    const allowedTypes = ['.xml', '.mxl', '.musicxml'];
    const ext = path.extname(file.originalname).toLowerCase();
    if (allowedTypes.includes(ext)) {
      cb(null, true);
    } else {
      cb(new Error('Only MusicXML files are allowed'));
    }
  },
  limits: {
    fileSize: 10 * 1024 * 1024, // 10MB
  },
});

// 获取乐谱列表
router.get(
  '/',
  query('page').optional().isInt({ min: 1 }),
  query('limit').optional().isInt({ min: 1, max: 100 }),
  query('difficulty').optional().isIn(['BEGINNER', 'INTERMEDIATE', 'ADVANCED']),
  validate,
  async (req, res, next) => {
    try {
      const { page, limit, difficulty, category, search } = req.query;
      
      const result = await scoreService.getScores({
        page: page ? parseInt(page as string) : undefined,
        limit: limit ? parseInt(limit as string) : undefined,
        difficulty: difficulty as string,
        category: category as string,
        search: search as string,
      });

      res.json({
        success: true,
        data: result.scores,
        pagination: result.pagination,
      });
    } catch (error) {
      next(error);
    }
  }
);

// 获取推荐乐谱
router.get('/recommended', async (req, res, next) => {
  try {
    const limit = parseInt(req.query.limit as string) || 10;
    const scores = await scoreService.getRecommendedScores(limit);
    res.json({ success: true, data: scores });
  } catch (error) {
    next(error);
  }
});

// 搜索乐谱
router.get('/search', async (req, res, next) => {
  try {
    const { q } = req.query;
    if (!q) {
      throw new AppError('Search query is required', 400);
    }
    const scores = await scoreService.searchScores(q as string);
    res.json({ success: true, data: scores });
  } catch (error) {
    next(error);
  }
});

// 获取单个乐谱
router.get(
  '/:id',
  param('id').isUUID(),
  validate,
  async (req, res, next) => {
    try {
      const score = await scoreService.getScoreById(req.params.id);
      if (!score) {
        throw new AppError('Score not found', 404);
      }
      res.json({ success: true, data: score });
    } catch (error) {
      next(error);
    }
  }
);

// 上传乐谱
router.post(
  '/',
  upload.single('file'),
  async (req, res, next) => {
    try {
      if (!req.file) {
        throw new AppError('No file uploaded', 400);
      }

      const { title, composer, arranger, difficulty, category, source, license } = req.body;

      if (!title || !composer) {
        throw new AppError('Title and composer are required', 400);
      }

      const score = await scoreService.createScore({
        title,
        composer,
        arranger,
        difficulty: difficulty as string || 'BEGINNER',
        musicXmlPath: req.file.path,
        fileSize: req.file.size,
        category,
        source,
        license,
      });

      res.status(201).json({
        success: true,
        data: score,
        message: 'Score uploaded successfully',
      });
    } catch (error) {
      next(error);
    }
  }
);

// 更新乐谱
router.patch(
  '/:id',
  param('id').isUUID(),
  validate,
  async (req, res, next) => {
    try {
      const score = await scoreService.updateScore(req.params.id, req.body);
      res.json({ success: true, data: score });
    } catch (error) {
      next(error);
    }
  }
);

// 发布乐谱
router.post(
  '/:id/publish',
  param('id').isUUID(),
  validate,
  async (req, res, next) => {
    try {
      const score = await scoreService.publishScore(req.params.id);
      res.json({ success: true, data: score, message: 'Score published' });
    } catch (error) {
      next(error);
    }
  }
);

// 删除乐谱
router.delete(
  '/:id',
  param('id').isUUID(),
  validate,
  async (req, res, next) => {
    try {
      await scoreService.deleteScore(req.params.id);
      res.json({ success: true, message: 'Score deleted' });
    } catch (error) {
      next(error);
    }
  }
);

// GET /api/scores/:id/xml - 下载乐谱 MusicXML 文件
router.get(
  '/:id/xml',
  param('id').isUUID(),
  validate,
  async (req, res, next) => {
    try {
      const score = await prisma.score.findUnique({
        where: { id: req.params.id },
        select: { musicXmlPath: true, title: true },
      });

      if (!score) {
        throw new AppError('乐谱不存在', 404);
      }

      if (!fs.existsSync(score.musicXmlPath)) {
        throw new AppError('乐谱文件不存在', 404);
      }

      const ext = path.extname(score.musicXmlPath).toLowerCase();
      const contentType =
        ext === '.mxl'
          ? 'application/vnd.recordare.musicxml'
          : 'application/xml; charset=utf-8';

      res.setHeader('Content-Type', contentType);
      res.setHeader(
        'Content-Disposition',
        `attachment; filename="${encodeURIComponent(score.title)}.xml"`
      );

      const stream = fs.createReadStream(score.musicXmlPath);
      stream.pipe(res);
    } catch (error) {
      next(error);
    }
  }
);

// POST /api/scores/:id/favorite - 收藏乐谱
router.post(
  '/:id/favorite',
  authMiddleware,
  param('id').isUUID(),
  validate,
  async (req: any, res, next) => {
    try {
      const score = await prisma.score.findUnique({
        where: { id: req.params.id },
      });

      if (!score) {
        throw new AppError('乐谱不存在', 404);
      }

      // 检查是否已收藏
      const user = await prisma.user.findUnique({
        where: { id: req.userId },
        include: {
          favorites: {
            where: { id: req.params.id },
          },
        },
      });

      if (user && user.favorites.length > 0) {
        return res.json({ success: true, message: '已收藏过该乐谱' });
      }

      // 添加收藏
      await prisma.user.update({
        where: { id: req.userId },
        data: {
          favorites: {
            connect: { id: req.params.id },
          },
        },
      });

      // 更新收藏计数
      await prisma.score.update({
        where: { id: req.params.id },
        data: { favoriteCount: { increment: 1 } },
      });

      logger.info(`Score favorited: ${req.params.id} by user ${req.userId}`);
      res.json({ success: true, message: '收藏成功' });
    } catch (error) {
      next(error);
    }
  }
);

// DELETE /api/scores/:id/favorite - 取消收藏
router.delete(
  '/:id/favorite',
  authMiddleware,
  param('id').isUUID(),
  validate,
  async (req: any, res, next) => {
    try {
      const score = await prisma.score.findUnique({
        where: { id: req.params.id },
      });

      if (!score) {
        throw new AppError('乐谱不存在', 404);
      }

      // 检查是否已收藏
      const user = await prisma.user.findUnique({
        where: { id: req.userId },
        include: {
          favorites: {
            where: { id: req.params.id },
          },
        },
      });

      if (!user || user.favorites.length === 0) {
        return res.json({ success: true, message: '未收藏该乐谱' });
      }

      // 取消收藏
      await prisma.user.update({
        where: { id: req.userId },
        data: {
          favorites: {
            disconnect: { id: req.params.id },
          },
        },
      });

      // 更新收藏计数
      await prisma.score.update({
        where: { id: req.params.id },
        data: { favoriteCount: { decrement: 1 } },
      });

      logger.info(`Score unfavorited: ${req.params.id} by user ${req.userId}`);
      res.json({ success: true, message: '已取消收藏' });
    } catch (error) {
      next(error);
    }
  }
);

export default router;
