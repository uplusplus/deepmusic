import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

async function main() {
  console.log('🌱 Seeding database...\n');

  // 创建标签
  const tags = await Promise.all([
    prisma.tag.upsert({
      where: { name: '古典' },
      update: {},
      create: { name: '古典' },
    }),
    prisma.tag.upsert({
      where: { name: '流行' },
      update: {},
      create: { name: '流行' },
    }),
    prisma.tag.upsert({
      where: { name: '影视' },
      update: {},
      create: { name: '影视' },
    }),
    prisma.tag.upsert({
      where: { name: '民歌' },
      update: {},
      create: { name: '民歌' },
    }),
    prisma.tag.upsert({
      where: { name: '爵士' },
      update: {},
      create: { name: '爵士' },
    }),
    prisma.tag.upsert({
      where: { name: '浪漫' },
      update: {},
      create: { name: '浪漫' },
    }),
    prisma.tag.upsert({
      where: { name: '入门' },
      update: {},
      create: { name: '入门' },
    }),
  ]);

  console.log(`✅ Created ${tags.length} tags`);

  console.log('\n✨ Seed completed!');
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
