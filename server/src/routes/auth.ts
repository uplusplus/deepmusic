import { Router } from 'express';

const router = Router();

// TODO: 实现用户认证
// POST /api/auth/register - 注册
// POST /api/auth/login - 登录
// POST /api/auth/logout - 登出
// GET /api/auth/me - 获取当前用户

router.post('/register', (req, res) => {
  res.json({ message: 'Register endpoint - TODO' });
});

router.post('/login', (req, res) => {
  res.json({ message: 'Login endpoint - TODO' });
});

router.get('/me', (req, res) => {
  res.json({ message: 'Get current user - TODO' });
});

export default router;
