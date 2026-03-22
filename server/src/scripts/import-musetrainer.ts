import { PrismaClient } from '@prisma/client';
import * as fs from 'fs';
import * as path from 'path';

const prisma = new PrismaClient();
const dir = 'D:\\08_ai\\workspace\\deepmusic\\server\\uploads\\scores';

// 数据库已有文件 (不重复导入)
const existingFiles = new Set([
  'CharlesGounod_Meditation.xml','Nocturne_No._20_in_C_Minor.xml','Fur_Elise.xml',
  'Clementi_Sonatina_Op36_No3_Mvt1.xml','Bach_Prelude_CMajor_BWV846.xml','Dichterliebe01.xml',
  'Clementi_Sonatina_Op36_No1_Mvt2.xml','Bach_Air_on_G_String.xml','Mozart_DasVeilchen.xml',
  'Clementi_Sonatina_Op36_No1_Mvt1.xml','Beethoven_AnDieFerneGeliebte.xml','Debussy_Mandoline.xml',
  'Mozart_AnChloe.xml','Brahms_Wie_Melodien.xml','Minuet_in_G_Major_Bach.xml',
  'Carol_of_the_Bells_easy_piano.xml','Clementi_Sonatina_Op36_No3_Mvt2.xml',
  'Beethoven_Fur_Elise_Complete.musicxml','Mozart_Sonata16_Mvt1.musicxml',
  'Mozart_Sonata16_Mvt2.musicxml','Mozart_Sonata16_Mvt3.musicxml'
]);

// 映射文件名 → 中文标题
const titleMap: Record<string, { title: string; composer: string; difficulty: string; category: string }> = {
  'Clair_de_Lune__Debussy.xml': { title: '德彪西 月光 (Clair de Lune)', composer: '德彪西', difficulty: 'ADVANCED', category: 'classical' },
  'Piano_Sonata_No._11_K._331_3rd_Movement_Rondo_alla_Turca.xml': { title: '土耳其进行曲 (Rondo alla Turca)', composer: '莫扎特', difficulty: 'ADVANCED', category: 'classical' },
  'Canon_in_D.xml': { title: '卡农 (Canon in D)', composer: '帕赫贝尔', difficulty: 'BEGINNER', category: 'classical' },
  'Chopin_-_Nocturne_Op_9_No_2_E_Flat_Major.xml': { title: '肖邦 夜曲 Op.9 No.2', composer: '肖邦', difficulty: 'ADVANCED', category: 'classical' },
  'Hungarian_Dance_No_5_in_G_Minor.xml': { title: '勃拉姆斯 匈牙利舞曲第五号', composer: '勃拉姆斯', difficulty: 'ADVANCED', category: 'classical' },
  'Ave_Maria_D839_-_Schubert_-_Solo_Piano_Arrg..xml': { title: '舒伯特 圣母颂 (Ave Maria)', composer: '舒伯特', difficulty: 'INTERMEDIATE', category: 'classical' },
  'Chopin_-_Ballade_no._1_in_G_minor_Op._23.xml': { title: '肖邦 叙事曲 No.1', composer: '肖邦', difficulty: 'ADVANCED', category: 'classical' },
  'Beethoven_Symphony_No._5_1st_movement_Piano_solo.xml': { title: '贝多芬 第五交响曲 (命运) 钢琴版', composer: '贝多芬', difficulty: 'ADVANCED', category: 'classical' },
  'Prlude_Opus_28_No._4_in_E_Minor__Chopin.xml': { title: '肖邦 E小调前奏曲 Op.28 No.4', composer: '肖邦', difficulty: 'INTERMEDIATE', category: 'classical' },
  'Liebestraum_No._3_in_A_Major.xml': { title: '李斯特 爱之梦 No.3', composer: '李斯特', difficulty: 'ADVANCED', category: 'classical' },
  'G_Minor_Bach_Original.xml': { title: '巴赫 G小调小步舞曲', composer: '巴赫', difficulty: 'BEGINNER', category: 'classical' },
  'Dance_of_the_sugar_plum_fairy.xml': { title: '糖果仙子舞曲 (胡桃夹子)', composer: '柴可夫斯基', difficulty: 'INTERMEDIATE', category: 'classical' },
  'Erik_Satie_-_Gymnopedie_No.1.xml': { title: '萨蒂 裸体歌舞 No.1', composer: '萨蒂', difficulty: 'INTERMEDIATE', category: 'classical' },
  'Greensleeves_for_Piano_easy_and_beautiful.xml': { title: '绿袖子 (Greensleeves)', composer: '英国民歌', difficulty: 'BEGINNER', category: 'folk' },
  'Happy_Birthday_To_You_Piano.xml': { title: '生日快乐 (Happy Birthday)', composer: '传统', difficulty: 'BEGINNER', category: 'folk' },
  'Ode_to_Joy_Easy_variation.xml': { title: '欢乐颂 简易变奏 (Ode to Joy)', composer: '贝多芬', difficulty: 'BEGINNER', category: 'classical' },
  'Bella_Ciao.xml': { title: 'Bella Ciao (朋友再见)', composer: '意大利民歌', difficulty: 'BEGINNER', category: 'folk' },
  'moonlight_sonata_3rd_movement.xml': { title: '月光奏鸣曲 第三乐章', composer: '贝多芬', difficulty: 'ADVANCED', category: 'classical' },
};

async function main() {
  let imported = 0;
  for (const [file, meta] of Object.entries(titleMap)) {
    if (existingFiles.has(file)) continue;
    
    const filePath = path.join(dir, file);
    if (!fs.existsSync(filePath)) { console.log(`Skip: ${file}`); continue; }
    
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

    const data = {
      title: meta.title, composer: meta.composer, difficulty: meta.difficulty, category: meta.category,
      timeSignature, keySignature, tempo, measures, duration,
      musicXmlPath: `uploads/scores/${file}`, fileSize,
      status: 'PUBLISHED', isPublic: true,
    };

    await prisma.score.create({ data });
    console.log(`✅ ${meta.title} (${measures}m, ${(fileSize/1024).toFixed(0)}KB)`);
    imported++;
  }
  console.log(`\nImported: ${imported}, Total: ${await prisma.score.count()}`);
}
main().finally(() => prisma.$disconnect());
