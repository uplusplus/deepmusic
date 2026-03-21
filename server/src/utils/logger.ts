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

export const morganStream = {
  write: (message: string) => {
    logger.info(message.trim());
  },
};

// Morgan 格式：method url status response-time ms
export const httpLogger = morgan(
  ':method :url :status :response-time[3]ms - :res[content-length]',
  { stream: morganStream }
);
