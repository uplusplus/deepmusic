import { PrismaClient } from '@prisma/client';
const prisma = new PrismaClient();

async function main() {
  // 查出占位曲目
  const placeholders = await prisma.score.findMany({
    where: { fileSize: { lt: 15000 } },
    select: { id: true, title: true, measures: true }
  });
  console.log('Found', placeholders.length, 'placeholders');
  
  // 删除关联记录
  for (const score of placeholders) {
    await prisma.practiceRecord.deleteMany({ where: { scoreId: score.id } }).catch(() => {});
    await prisma.practiceSession.deleteMany({ where: { scoreId: score.id } }).catch(() => {});
    // 删除收藏关联
    await prisma.score.update({
      where: { id: score.id },
      data: { favorites: { set: [] } }
    }).catch(() => {});
  }
  
  // 删除占位曲目
  const deleted = await prisma.score.deleteMany({ where: { fileSize: { lt: 15000 } } });
  console.log('Deleted:', deleted.count);
  
  const remaining = await prisma.score.count();
  console.log('Remaining:', remaining);
  
  const scores = await prisma.score.findMany({ 
    select: { title: true, measures: true, fileSize: true }, 
    orderBy: { measures: 'desc' } 
  });
  for (const s of scores) {
    console.log('  ' + s.title + ' (' + s.measures + 'm, ' + Math.round(s.fileSize/1024) + 'KB)');
  }
}

main().finally(() => prisma.$disconnect());
