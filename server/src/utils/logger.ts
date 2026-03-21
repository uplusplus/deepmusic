import winston from 'winston';

const { combine, timestamp, printf, colorize } = winston.format;

const logFormat = printf(({ level, message, timestamp }) => {
  return `${timestamp} [${level}]: ${message}`;
});

export const logger = winston.createLogger({
  level: process.env.LOG_LEVEL || 'info',
  format: combine(
    timestamp({ format: 'YYYY-MM-DD HH:mm:ss' }),
    logFormat
  ),
  transports: [
    new winston.transports.Console({
      format: combine(colorize(), logFormat),
    }),
    new winston.transports.File({
      filename: 'logs/error.log',
      level: 'error',
    }),
    new winston.transports.File({
      filename: 'logs/combined.log',
    }),
  ],
});

// Morgan HTTP 日志流，输出到 Winston
import morgan from 'morgan';
import type { Request, Response } from 'express';

export const morganStream = {
  write: (message: string) => {
    logger.info(message.trim());
  },
};

// 自定义 token: 客户端标识
morgan.token('client', (req: Request) => {
  return req.headers['x-client'] as string || '-';
});

// 自定义 token: 用户 ID (来自 auth 中间件)
morgan.token('uid', (req: any) => {
  return req.userId ? req.userId.substring(0, 8) : '-';
});

// Morgan 格式: 包含客户端标识、用户ID、请求详情
export const httpLogger = morgan(
  '[:client] :method :url :status :response-time[3]ms | uid=:uid | :req[content-length]→:res[content-length]',
  { stream: morganStream }
);
