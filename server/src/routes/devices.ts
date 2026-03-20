import { Router } from 'express';
import { body, param } from 'express-validator';
import { validate } from '../middleware/validate.js';
import { AppError } from '../middleware/error.js';
import { authMiddleware } from './auth.js';
import { PrismaClient } from '@prisma/client';
import { logger } from '../utils/logger.js';

const router = Router();
const prisma = new PrismaClient();

// 所有 devices 路由都需要认证
router.use(authMiddleware);

// GET /api/devices - 获取当前用户的设备列表
router.get('/', async (req: any, res, next) => {
  try {
    const devices = await prisma.device.findMany({
      where: { userId: req.userId },
      orderBy: { lastConnected: 'desc' },
    });

    res.json({ success: true, data: devices });
  } catch (error) {
    next(error);
  }
});

// POST /api/devices - 注册/绑定设备
router.post(
  '/',
  body('name').notEmpty().withMessage('设备名称不能为空'),
  body('manufacturer').optional().isString(),
  body('model').optional().isString(),
  validate,
  async (req: any, res, next) => {
    try {
      const { name, manufacturer, model } = req.body;

      // 检查是否已注册 (同名设备)
      const existing = await prisma.device.findFirst({
        where: {
          userId: req.userId,
          name,
        },
      });

      if (existing) {
        // 更新已存在的设备
        const updated = await prisma.device.update({
          where: { id: existing.id },
          data: {
            manufacturer: manufacturer || existing.manufacturer,
            model: model || existing.model,
            lastConnected: new Date(),
          },
        });

        return res.json({
          success: true,
          data: updated,
          message: '设备信息已更新',
        });
      }

      // 创建新设备记录
      const device = await prisma.device.create({
        data: {
          userId: req.userId,
          name,
          manufacturer,
          model,
          lastConnected: new Date(),
        },
      });

      logger.info(`Device registered: ${name} for user ${req.userId}`);

      res.status(201).json({
        success: true,
        data: device,
      });
    } catch (error) {
      next(error);
    }
  }
);

// PATCH /api/devices/:id - 更新设备信息
router.patch(
  '/:id',
  param('id').isUUID(),
  body('name').optional().isString(),
  body('manufacturer').optional().isString(),
  body('model').optional().isString(),
  validate,
  async (req: any, res, next) => {
    try {
      const device = await prisma.device.findFirst({
        where: {
          id: req.params.id,
          userId: req.userId,
        },
      });

      if (!device) {
        throw new AppError('设备不存在', 404);
      }

      const updated = await prisma.device.update({
        where: { id: req.params.id },
        data: {
          ...req.body,
          lastConnected: new Date(),
        },
      });

      res.json({ success: true, data: updated });
    } catch (error) {
      next(error);
    }
  }
);

// DELETE /api/devices/:id - 删除设备
router.delete(
  '/:id',
  param('id').isUUID(),
  validate,
  async (req: any, res, next) => {
    try {
      const device = await prisma.device.findFirst({
        where: {
          id: req.params.id,
          userId: req.userId,
        },
      });

      if (!device) {
        throw new AppError('设备不存在', 404);
      }

      await prisma.device.delete({
        where: { id: req.params.id },
      });

      logger.info(`Device deleted: ${req.params.id}`);
      res.json({ success: true, message: '设备已删除' });
    } catch (error) {
      next(error);
    }
  }
);

// POST /api/devices/:id/connect - 记录设备连接
router.post(
  '/:id/connect',
  param('id').isUUID(),
  validate,
  async (req: any, res, next) => {
    try {
      const device = await prisma.device.findFirst({
        where: {
          id: req.params.id,
          userId: req.userId,
        },
      });

      if (!device) {
        throw new AppError('设备不存在', 404);
      }

      const updated = await prisma.device.update({
        where: { id: req.params.id },
        data: { lastConnected: new Date() },
      });

      logger.info(`Device connected: ${device.name}`);
      res.json({ success: true, data: updated });
    } catch (error) {
      next(error);
    }
  }
);

export default router;
