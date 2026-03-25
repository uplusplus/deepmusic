import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import rateLimit from 'express-rate-limit';
import dotenv from 'dotenv';
import { logger, httpLogger } from './utils/logger.js';
import { errorHandler } from './middleware/error.js';
import { notFoundHandler } from './middleware/notFound.js';

// Routes
import scoreRoutes from './routes/scores.js';
import authRoutes from './routes/auth.js';
import practiceRoutes from './routes/practice.js';
import deviceRoutes from './routes/devices.js';
import userRoutes from './routes/user.js';

dotenv.config();

const app = express();
const PORT = Number(process.env.PORT) || 3000;

// Middleware
app.use(helmet({
  contentSecurityPolicy: {
    directives: {
      ...helmet.contentSecurityPolicy.getDefaultDirectives(),
      'script-src': ["'self'", "'unsafe-inline'"],
      'script-src-attr': ["'unsafe-inline'"],
    },
  },
}));
app.use(cors({
  origin: process.env.CORS_ORIGIN || '*',
  credentials: true,
}));

// Rate limiting
const limiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 100, // limit each IP to 100 requests per windowMs
  message: { error: 'Too many requests, please try again later.' },
});
app.use('/api/', limiter);

app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true }));
// HTTP 请求日志
app.use(httpLogger);

// Static files
app.use('/uploads', express.static(process.env.UPLOAD_DIR || './uploads'));
app.use(express.static('public'));

// Health check
app.get('/health', (req, res) => {
  res.json({
    status: 'ok',
    timestamp: new Date().toISOString(),
    version: '1.0.0',
  });
});

// API Routes
app.use('/api/scores', scoreRoutes);
app.use('/api/auth', authRoutes);
app.use('/api/practice', practiceRoutes);
app.use('/api/devices', deviceRoutes);
app.use('/api/user', userRoutes);

// Error handling
app.use(notFoundHandler);
app.use(errorHandler);

// Start server
app.listen(PORT, '0.0.0.0', () => {
  logger.info(`🚀 DeepMusic Server running on 0.0.0.0:${PORT}`);
  logger.info(`📍 Health check: http://0.0.0.0:${PORT}/health`);
  logger.info(`🎵 API base URL: http://0.0.0.0:${PORT}/api`);
});

export default app;
