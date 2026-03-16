import { Router } from 'express';
import { body, query, param } from 'express-validator';
import { validate } from '../middleware/validate.js';
import { AppError } from '../middleware/error.js';
import * as scoreService from '../services/score.service.js';
import { Difficulty } from '@prisma/client';
import multer from 'multer';
import path from 'path';
import fs from 'fs';

const router = Router();

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
        difficulty: difficulty as Difficulty,
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
        difficulty: difficulty as Difficulty || 'BEGINNER',
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

export default router;
