const fs = require('fs');
const path = require('path');
const { PrismaClient } = require('@prisma/client');
const prisma = new PrismaClient();

// 映射：真实文件 → 数据库曲目
const mappings = [
  // 钢琴独奏曲
  { file: 'Bach_Prelude_CMajor_BWV846.xml', title: '巴赫C大调前奏曲 BWV 846', composer: '巴赫', difficulty: 'INTERMEDIATE', category: 'classical' },
  { file: 'Bach_Air_on_G_String.xml', title: 'G弦上的咏叹调', composer: '巴赫', difficulty: 'INTERMEDIATE', category: 'classical' },
  { file: 'Clementi_Sonatina_Op36_No1_Mvt1.xml', title: '克莱门蒂小奏鸣曲 Op.36 No.1 第一乐章', composer: '克莱门蒂', difficulty: 'BEGINNER', category: 'classical' },
  { file: 'Clementi_Sonatina_Op36_No1_Mvt2.xml', title: '克莱门蒂小奏鸣曲 Op.36 No.1 第二乐章', composer: '克莱门蒂', difficulty: 'BEGINNER', category: 'classical' },
  { file: 'Clementi_Sonatina_Op36_No3_Mvt1.xml', title: '克莱门蒂小奏鸣曲 Op.36 No.3 第一乐章', composer: '克莱门蒂', difficulty: 'INTERMEDIATE', category: 'classical' },
  { file: 'Clementi_Sonatina_Op36_No3_Mvt2.xml', title: '克莱门蒂小奏鸣曲 Op.36 No.3 第二乐章', composer: '克莱门蒂', difficulty: 'INTERMEDIATE', category: 'classical' },
  { file: 'CharlesGounod_Meditation.xml', title: '古诺 - 圣母颂（巴赫前奏曲上的冥想）', composer: '古诺', difficulty: 'ADVANCED', category: 'classical' },
  { file: 'Beethoven_AnDieFerneGeliebte.xml', title: '贝多芬 - 致远方的爱人', composer: '贝多芬', difficulty: 'ADVANCED', category: 'classical' },
  { file: 'Dichterliebe01.xml', title: '舒曼 - 诗人之恋 第一首', composer: '舒曼', difficulty: 'ADVANCED', category: 'classical' },
  { file: 'Debussy_Mandoline.xml', title: '德彪西 - 曼陀铃', composer: '德彪西', difficulty: 'ADVANCED', category: 'classical' },
  { file: 'Mozart_AnChloe.xml', title: '莫扎特 - 致克洛埃', composer: '莫扎特', difficulty: 'INTERMEDIATE', category: 'classical' },
  { file: 'Mozart_DasVeilchen.xml', title: '莫扎特 - 紫罗兰', composer: '莫扎特', difficulty: 'INTERMEDIATE', category: 'classical' },
  { file: 'Brahms_Wie_Melodien.xml', title: '勃拉姆斯 - 旋律如何流动', composer: '勃拉姆斯', difficulty: 'ADVANCED', category: 'classical' },
  { file: 'Gretchaninov_A_Boring_Story.musicxml', title: '格列恰尼诺夫 - 无聊的故事', composer: '格列恰尼诺夫', difficulty: 'INTERMEDIATE', category: 'classical' },
  { file: 'Land_der_Berge.musicxml', title: '奥地利国歌', composer: '莫扎特/霍尔泽', difficulty: 'BEGINNER', category: 'folk' },
  { file: 'Mozart_String_Quartet_in_G_K._387_1st_Mvmnt_excerpt.musicxml', title: '莫扎特 G大调弦乐四重奏 K.387 第一乐章', composer: '莫扎特', difficulty: 'ADVANCED', category: 'classical' },
];

// 需要删除的旧占位曲目 (将被替换)
const titlesToDelete = [
  '巴赫C大调前奏曲 BWV 846', // 不在原库里，新增
  // 原库里29首如果要替换，需要在这里列出
];

async function main() {
  const dir = 'D:\\08_ai\\workspace\\deepmusic\\server\\uploads\\scores';
  
  let imported = 0;
  let skipped = 0;

  for (const mapping of mappings) {
    const filePath = path.join(dir, mapping.file);
    
    if (!fs.existsSync(filePath)) {
      console.log(`⚠️  文件不存在: ${mapping.file}`);
      skipped++;
      continue;
    }

    const xml = fs.readFileSync(filePath, 'utf-8');
    const fileSize = Buffer.byteLength(xml, 'utf-8');

    // 解析元数据
    const measuresMatch = xml.match(/<measure[\s>]/g);
    const measures = measuresMatch ? measuresMatch.length : 0;
    
    const timeSigMatch = xml.match(/<beats>(\d+)<\/beats>\s*<beat-type>(\d+)<\/beat-type>/);
    const timeSignature = timeSigMatch ? `${timeSigMatch[1]}/${timeSigMatch[2]}` : '4/4';
    
    const keyMatch = xml.match(/<fifths>(-?\d+)<\/fifths>/);
    const keyNames = ['C Major', 'G Major', 'D Major', 'A Major', 'E Major', 'B Major', 'F# Major', 'C# Major',
                      'F Major', 'Bb Major', 'Eb Major', 'Ab Major', 'Db Major', 'Gb Major', 'Cb Major'];
    const fifths = keyMatch ? parseInt(keyMatch[1]) : 0;
    const keySignature = (fifths >= 0 && fifths < 8) ? keyNames[fifths] :
                         (fifths < 0 && fifths >= -7) ? keyNames[8 - fifths] : 'C Major';
    
    const tempoMatch = xml.match(/<per-minute>(\d+)<\/per-minute>/);
    const tempo = tempoMatch ? parseInt(tempoMatch[1]) : 80;
    const duration = Math.round(measures * (60 / tempo) * 4);

    if (measures < 5) {
      console.log(`⚠️  ${mapping.title}: 只有 ${measures} 小节，跳过`);
      skipped++;
      continue;
    }

    // 检查是否已存在同名曲目
    const existing = await prisma.score.findFirst({
      where: { title: mapping.title },
    });

    const scoreData = {
      title: mapping.title,
      composer: mapping.composer,
      difficulty: mapping.difficulty,
      category: mapping.category,
      timeSignature,
      keySignature,
      tempo,
      measures,
      duration,
      musicXmlPath: `uploads/scores/${mapping.file}`,
      fileSize,
      status: 'PUBLISHED',
      isPublic: true,
    };

    if (existing) {
      // 更新已有记录
      await prisma.score.update({
        where: { id: existing.id },
        data: { ...scoreData, updatedAt: new Date() },
      });
      console.log(`🔄 更新: ${mapping.title} (${measures} 小节, ${duration}秒, ${(fileSize/1024).toFixed(0)}KB)`);
    } else {
      // 创建新记录
      await prisma.score.create({ data: scoreData });
      console.log(`✅ 新增: ${mapping.title} (${measures} 小节, ${duration}秒, ${(fileSize/1024).toFixed(0)}KB)`);
    }
    imported++;
  }

  console.log(`\n📊 完成! 导入 ${imported} 首, 跳过 ${skipped} 首`);

  // 显示最终统计
  const total = await prisma.score.count();
  console.log(`📚 数据库总计: ${total} 首乐谱`);
}

main().catch(console.error).finally(() => prisma.$disconnect());
