import { PrismaClient } from '@prisma/client';
import { logger } from '../utils/logger.js';

const prisma = new PrismaClient();

// 获取乐谱列表
export const getScores = async (options: {
  page?: number;
  limit?: number;
  difficulty?: string;
  category?: string;
  search?: string;
}) => {
  const { page = 1, limit = 20, difficulty, category, search } = options;
  const skip = (page - 1) * limit;

  const where = {
    status: 'PUBLISHED',
    isPublic: true,
    ...(difficulty && { difficulty }),
    ...(category && { category }),
    ...(search && {
      OR: [
        { title: { contains: search, mode: 'insensitive' as const } },
        { composer: { contains: search, mode: 'insensitive' as const } },
      ],
    }),
  };

  const [scores, total] = await Promise.all([
    prisma.score.findMany({
      where,
      skip,
      take: limit,
      orderBy: { createdAt: 'desc' },
      include: {
        tags: true,
      },
    }),
    prisma.score.count({ where }),
  ]);

  return {
    scores,
    pagination: {
      page,
      limit,
      total,
      totalPages: Math.ceil(total / limit),
    },
  };
};

// 获取单个乐谱
export const getScoreById = async (id: string) => {
  const score = await prisma.score.findUnique({
    where: { id },
    include: {
      tags: true,
    },
  });

  if (!score) {
    return null;
  }

  // 增加播放计数
  await prisma.score.update({
    where: { id },
    data: { playCount: { increment: 1 } },
  });

  return score;
};

// 创建乐谱
export const createScore = async (data: {
  title: string;
  composer: string;
  arranger?: string;
  difficulty?: string;
  musicXmlPath: string;
  fileSize: number;
  duration?: number;
  measures?: number;
  timeSignature?: string;
  keySignature?: string;
  tempo?: number;
  category?: string;
  source?: string;
  license?: string;
}) => {
  const score = await prisma.score.create({
    data: {
      ...data,
      status: 'DRAFT',
    },
  });

  logger.info(`Created score: ${score.id} - ${score.title}`);
  return score;
};

// 更新乐谱
export const updateScore = async (id: string, data: Partial<{
  title: string;
  composer: string;
  arranger: string;
  difficulty: string;
  category: string;
  status: string;
  isPublic: boolean;
}>) => {
  const score = await prisma.score.update({
    where: { id },
    data,
  });

  logger.info(`Updated score: ${id}`);
  return score;
};

// 删除乐谱
export const deleteScore = async (id: string) => {
  await prisma.score.delete({
    where: { id },
  });

  logger.info(`Deleted score: ${id}`);
};

// 发布乐谱
export const publishScore = async (id: string) => {
  const score = await prisma.score.update({
    where: { id },
    data: {
      status: 'PUBLISHED',
      publishedAt: new Date(),
    },
  });

  logger.info(`Published score: ${id}`);
  return score;
};

// 获取推荐乐谱
export const getRecommendedScores = async (limit: number = 10) => {
  return prisma.score.findMany({
    where: {
      status: 'PUBLISHED',
      isPublic: true,
    },
    take: limit,
    orderBy: [
      { playCount: 'desc' },
      { favoriteCount: 'desc' },
    ],
  });
};

// 搜索乐谱
export const searchScores = async (query: string, limit: number = 20) => {
  return prisma.score.findMany({
    where: {
      status: 'PUBLISHED',
      isPublic: true,
      OR: [
        { title: { contains: query, mode: 'insensitive' } },
        { composer: { contains: query, mode: 'insensitive' } },
        { category: { contains: query, mode: 'insensitive' } },
      ],
    },
    take: limit,
    orderBy: { playCount: 'desc' },
  });
};
