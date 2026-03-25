import { PrismaClient } from '@prisma/client';
import * as fs from 'fs';
import * as path from 'path';

const prisma = new PrismaClient();
const dir = 'D:\\08_ai\\workspace\\deepmusic\\server\\uploads\\scores';

const pieces = [
  { file: 'Beethoven_Fur_Elise_Complete.musicxml', title: '致爱丽丝 完整版 (Für Elise)', composer: '贝多芬', difficulty: 'INTERMEDIATE', category: 'classical' },
  { file: 'Mozart_Sonata16_Mvt1.musicxml', title: '莫扎特奏鸣曲 K.545 第一乐章', composer: '莫扎特', difficulty: 'INTERMEDIATE', category: 'classical' },
  { file: 'Mozart_Sonata16_Mvt2.musicxml', title: '莫扎特奏鸣曲 K.545 第二乐章', composer: '莫扎特', difficulty: 'INTERMEDIATE', category: 'classical' },
  { file: 'Mozart_Sonata16_Mvt3.musicxml', title: '莫扎特奏鸣曲 K.545 第三乐章', composer: '莫扎特', difficulty: 'ADVANCED', category: 'classical' },
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
