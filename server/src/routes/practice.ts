import { Router } from 'express';

const router = Router();

// TODO: 实现练习记录
// POST /api/practice - 创建练习记录
// GET /api/practice - 获取练习历史
// GET /api/practice/stats - 获取统计数据

router.post('/', (req, res) => {
  res.json({ message: 'Create practice record - TODO' });
});

router.get('/', (req, res) => {
  res.json({ message: 'Get practice history - TODO' });
});

router.get('/stats', (req, res) => {
  res.json({ message: 'Get practice stats - TODO' });
});

export default router;
