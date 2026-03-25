import { PrismaClient } from '@prisma/client';
import * as fs from 'fs';
import * as path from 'path';

const prisma = new PrismaClient();
const dir = 'D:\\08_ai\\workspace\\deepmusic\\server\\uploads\\scores';

const pieces = [
  { file: '致爱丽丝.xml', title: '致爱丽丝 (Für Elise)', composer: '贝多芬', difficulty: 'INTERMEDIATE', category: 'classical' },
  { file: '卡农.xml', title: '卡农 (Canon in D)', composer: '帕赫贝尔', difficulty: 'BEGINNER', category: 'classical' },
  { file: '天空之城.xml', title: '天空之城 (Castle in the Sky)', composer: '久石让', difficulty: 'BEGINNER', category: 'anime' },
  { file: '茉莉花.xml', title: '茉莉花 (Jasmine Flower)', composer: '中国民歌', difficulty: 'BEGINNER', category: 'folk' },
  { file: '小星星变奏曲.xml', title: '小星星变奏曲 (Twinkle Variations)', composer: '莫扎特', difficulty: 'BEGINNER', category: 'classical' },
  { file: '生日快乐.xml', title: '生日快乐 (Happy Birthday)', composer: '传统', difficulty: 'BEGINNER', category: 'folk' },
  { file: '欢乐颂.xml', title: '欢乐颂 (Ode to Joy)', composer: '贝多芬', difficulty: 'BEGINNER', category: 'classical' },
  { file: '铃儿响叮当.xml', title: '铃儿响叮当 (Jingle Bells)', composer: 'James Lord Pierpont', difficulty: 'BEGINNER', category: 'folk' },
];

async function main() {
  let imported = 0;
  for (const p of pieces) {
    const filePath = path.join(dir, p.file);
    if (!fs.existsSync(filePath)) { console.log(`Skip: ${p.file}`); continue; }
    
    const xml = fs.readFileSync(filePath, 'utf-8');
    const fileSize = Buffer.byteLength(xml, 'utf-8');
    const measures = (xml.match(/<measure[\s>]/g) || []).length;
    
    const tsMatch = xml.match(/<beats>(\d+)<\/beats>\s*<beat-type>(\d+)<\/beat-type>/);
    const timeSignature = tsMatch ? `${tsMatch[1]}/${tsMatch[2]}` : '4/4';
    
    const keyMatch = xml.match(/<fifths>(-?\d+)<\/fifths>/);
    const keyNames = ['C Major','G Major','D Major','A Major','E Major','B Major','F# Major','C# Major',
                      'F Major','Bb Major','Eb Major','Ab Major','Db Major','Gb Major','Cb Major'];
    const fifths = keyMatch ? parseInt(keyMatch[1]) : 0;
    const keySignature = (fifths >= 0) ? keyNames[fifths] : keyNames[8 - fifths];
    
    const tempoMatch = xml.match(/<per-minute>(\d+)<\/per-minute>/);
    const tempo = tempoMatch ? parseInt(tempoMatch[1]) : 80;
    const duration = Math.round(measures * (60 / tempo) * 4);

    const existing = await prisma.score.findFirst({ where: { title: p.title } });
    const data = {
      title: p.title, composer: p.composer, difficulty: p.difficulty, category: p.category,
      timeSignature, keySignature, tempo, measures, duration,
      musicXmlPath: `uploads/scores/${p.file}`, fileSize,
      status: 'PUBLISHED', isPublic: true,
    };

    if (existing) {
      await prisma.score.update({ where: { id: existing.id }, data: { ...data, updatedAt: new Date() } });
      console.log(`🔄 ${p.title} (${measures}m, ${duration}s)`);
    } else {
      await prisma.score.create({ data });
      console.log(`✅ ${p.title} (${measures}m, ${duration}s)`);
    }
    imported++;
  }
  console.log(`\nImported: ${imported}, Total: ${await prisma.score.count()}`);
}

main().finally(() => prisma.$disconnect());
