import { Router } from 'express';

const router = Router();

// TODO: 实现 MIDI 设备管理
// GET /api/devices - 获取设备列表
// POST /api/devices - 注册设备
// DELETE /api/devices/:id - 删除设备

router.get('/', (req, res) => {
  res.json({ message: 'Get devices - TODO' });
});

router.post('/', (req, res) => {
  res.json({ message: 'Register device - TODO' });
});

export default router;
