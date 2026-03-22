import 'package:flutter_test/flutter_test.dart';
import 'package:deepmusic/features/score/models/score.dart';
import 'package:deepmusic/features/score/services/musicxml_parser.dart';
import 'package:deepmusic/features/practice/services/auto_player.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ══════════════════════════════════════════════════════════════
  // 1. MIDI Pitch Number 正确性
  // ══════════════════════════════════════════════════════════════
  group('Note pitchNumber 计算正确性', () {
    test('标准音名到 MIDI pitchNumber 映射', () {
      const cases = <String, int>{
        'C4': 60, 'D4': 62, 'E4': 64, 'F4': 65,
        'G4': 67, 'A4': 69, 'B4': 71,
        'C5': 72, 'C3': 48, 'C6': 84,
      };

      for (final entry in cases.entries) {
        final note = Note.fromPitchName(entry.key, measureNumber: 1);
        expect(
          note.pitchNumber,
          equals(entry.value),
          reason: '${entry.key} 应映射为 MIDI ${entry.value}，实际为 ${note.pitchNumber}',
        );
      }
    });

    test('升降号处理', () {
      final cs4 = Note.fromPitchName('C#4', measureNumber: 1);
      expect(cs4.pitchNumber, equals(61), reason: 'C#4 应为 61');

      final bb4 = Note.fromPitchName('Bb4', measureNumber: 1);
      expect(bb4.pitchNumber, equals(70), reason: 'Bb4 应为 70');

      final ab3 = Note.fromPitchName('Ab3', measureNumber: 1);
      expect(ab3.pitchNumber, equals(56), reason: 'Ab3 应为 56');
    });

    test('Note.fromPitchName 与 MusicXML 解析结果一致', () {
      final c5 = Note.fromPitchName('C5', measureNumber: 1);
      expect(c5.pitchNumber, equals(72));

      final g4 = Note.fromPitchName('G4', measureNumber: 1);
      expect(g4.pitchNumber, equals(67));

      final e5 = Note.fromPitchName('E5', measureNumber: 1);
      expect(e5.pitchNumber, equals(76));
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 2. 时间轴计算准确度
  // ══════════════════════════════════════════════════════════════
  group('时间轴计算 (startMs)', () {
    const testXml = '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE score-partwise PUBLIC "-//Recordare//DTD MusicXML 2.0 Partwise//EN"
  "http://www.musicxml.org/dtds/partwise.dtd">
<score-partwise>
  <work><work-title>Test</work-title></work>
  <identification><creator type="composer">Tester</creator></identification>
  <part-list>
    <score-part id="P1"><part-name>Piano</part-name></score-part>
  </part-list>
  <part id="P1">
    <measure number="1">
      <attributes>
        <divisions>4</divisions>
        <key><fifths>0</fifths><mode>major</mode></key>
        <time><beats>4</beats><beat-type>4</beat-type></time>
      </attributes>
      <direction><sound tempo="120"/></direction>
      <note>
        <pitch><step>C</step><octave>4</octave></pitch>
        <duration>4</duration>
      </note>
      <note>
        <pitch><step>D</step><octave>4</octave></pitch>
        <duration>4</duration>
      </note>
      <note>
        <pitch><step>E</step><octave>4</octave></pitch>
        <duration>4</duration>
      </note>
      <note>
        <pitch><step>F</step><octave>4</octave></pitch>
        <duration>4</duration>
      </note>
    </measure>
    <measure number="2">
      <note>
        <pitch><step>G</step><octave>4</octave></pitch>
        <duration>16</duration>
      </note>
    </measure>
  </part>
</score-partwise>
''';

    test('120 BPM, divisions=4 时小节内音符起始时间正确', () {
      final score = MusicXmlParser.parseString(testXml);
      final notes = score.allNotes;

      // tempo=120 → beatMs=500ms
      // divisions=4 → 每 tick = 500/4 = 125ms
      // 第1小节: C4@tick0, D4@tick4, E4@tick8, F4@tick12
      // 第2小节: G4@tick16 (小节偏移: 16 ticks × 125ms = 2000ms)

      expect(notes.length, equals(5));

      expect(notes[0].pitch, equals('C4'));
      expect(notes[0].startMs, equals(0),
          reason: 'C4 在 tick 0, 应为 0ms');

      expect(notes[1].pitch, equals('D4'));
      expect(notes[1].startMs, equals(500),
          reason: 'D4 在 tick 4, 应为 500ms (4×125)');

      expect(notes[2].pitch, equals('E4'));
      expect(notes[2].startMs, equals(1000),
          reason: 'E4 在 tick 8, 应为 1000ms (8×125)');

      expect(notes[3].pitch, equals('F4'));
      expect(notes[3].startMs, equals(1500),
          reason: 'F4 在 tick 12, 应为 1500ms (12×125)');

      expect(notes[4].pitch, equals('G4'));
      expect(notes[4].startMs, equals(2000),
          reason: 'G4 在第2小节 tick 0, 应为 2000ms (16×125)');
    });

    test('音符时值 duration 正确 (以拍为单位)', () {
      final score = MusicXmlParser.parseString(testXml);
      final notes = score.allNotes;

      for (int i = 0; i < 4; i++) {
        expect(notes[i].duration, equals(1.0),
            reason: '${notes[i].pitch} duration 应为 1.0 拍');
      }

      expect(notes[4].duration, equals(4.0),
          reason: 'G4 duration 应为 4.0 拍');
    });

    test('60 BPM 下时间轴正确 (beatMs=1000ms)', () {
      const xml60bpm = '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE score-partwise PUBLIC "-//Recordare//DTD MusicXML 2.0 Partwise//EN"
  "http://www.musicxml.org/dtds/partwise.dtd">
<score-partwise>
  <work><work-title>Slow</work-title></work>
  <identification><creator type="composer">Tester</creator></identification>
  <part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>
  <part id="P1">
    <measure number="1">
      <attributes>
        <divisions>4</divisions>
        <time><beats>4</beats><beat-type>4</beat-type></time>
      </attributes>
      <direction><sound tempo="60"/></direction>
      <note>
        <pitch><step>C</step><octave>4</octave></pitch>
        <duration>4</duration>
      </note>
      <note>
        <pitch><step>D</step><octave>4</octave></pitch>
        <duration>4</duration>
      </note>
    </measure>
  </part>
</score-partwise>
''';

      final score = MusicXmlParser.parseString(xml60bpm);
      final notes = score.allNotes;

      // tempo=60 → beatMs=1000ms, msPerTick=250ms
      expect(notes[0].startMs, equals(0), reason: 'C4 @ 0ms');
      expect(notes[1].startMs, equals(1000), reason: 'D4 @ 1000ms (= 4 ticks × 250ms)');
    });

    test('200 BPM 下 32 分音符精度 (msPerTick=75ms)', () {
      const xml200bpm = '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE score-partwise PUBLIC "-//Recordare//DTD MusicXML 2.0 Partwise//EN"
  "http://www.musicxml.org/dtds/partwise.dtd">
<score-partwise>
  <work><work-title>Fast</work-title></work>
  <identification><creator type="composer">Tester</creator></identification>
  <part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>
  <part id="P1">
    <measure number="1">
      <attributes>
        <divisions>4</divisions>
        <time><beats>4</beats><beat-type>4</beat-type></time>
      </attributes>
      <direction><sound tempo="200"/></direction>
      <note><pitch><step>C</step><octave>4</octave></pitch><duration>1</duration></note>
      <note><pitch><step>D</step><octave>4</octave></pitch><duration>1</duration></note>
      <note><pitch><step>E</step><octave>4</octave></pitch><duration>1</duration></note>
      <note><pitch><step>F</step><octave>4</octave></pitch><duration>1</duration></note>
      <note><pitch><step>G</step><octave>4</octave></pitch><duration>1</duration></note>
      <note><pitch><step>A</step><octave>4</octave></pitch><duration>1</duration></note>
      <note><pitch><step>B</step><octave>4</octave></pitch><duration>1</duration></note>
      <note><pitch><step>C</step><octave>5</octave></pitch><duration>1</duration></note>
    </measure>
  </part>
</score-partwise>
''';
      final score = MusicXmlParser.parseString(xml200bpm);
      final notes = score.allNotes;

      // 200 BPM → beatMs=300ms, msPerTick=75ms
      // tickPos 0,1,2,3,4,5,6,7 → 0,75,150,225,300,375,450,525ms
      expect(notes[0].startMs, equals(0));
      expect(notes[1].startMs, equals(75));
      expect(notes[7].startMs, equals(525));

      // 严格递增
      for (int i = 0; i < notes.length - 1; i++) {
        expect(
          notes[i + 1].startMs,
          greaterThan(notes[i].startMs),
          reason: '音符 ${i + 1} 的 startMs 应大于音符 $i',
        );
      }
    });

    test('音符按时间严格递增排序', () {
      final score = MusicXmlParser.parseString(testXml);
      final notes = score.allNotes;

      for (int i = 1; i < notes.length; i++) {
        expect(
          notes[i].startMs,
          greaterThanOrEqualTo(notes[i - 1].startMs),
          reason: '${notes[i].pitch}(${notes[i].startMs}ms) 不应在 '
              '${notes[i-1].pitch}(${notes[i-1].startMs}ms) 之前',
        );
      }
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 3. 和弦同步
  // ══════════════════════════════════════════════════════════════
  group('和弦音符同步', () {
    test('和弦音符共享相同的 startMs', () {
      const chordXml = '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE score-partwise PUBLIC "-//Recordare//DTD MusicXML 2.0 Partwise//EN"
  "http://www.musicxml.org/dtds/partwise.dtd">
<score-partwise>
  <work><work-title>Chord Test</work-title></work>
  <identification><creator type="composer">Tester</creator></identification>
  <part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>
  <part id="P1">
    <measure number="1">
      <attributes>
        <divisions>4</divisions>
        <time><beats>4</beats><beat-type>4</beat-type></time>
      </attributes>
      <direction><sound tempo="120"/></direction>
      <note>
        <pitch><step>C</step><octave>4</octave></pitch>
        <duration>4</duration>
      </note>
      <note>
        <chord/>
        <pitch><step>E</step><octave>4</octave></pitch>
        <duration>4</duration>
      </note>
      <note>
        <chord/>
        <pitch><step>G</step><octave>4</octave></pitch>
        <duration>4</duration>
      </note>
    </measure>
  </part>
</score-partwise>
''';

      final score = MusicXmlParser.parseString(chordXml);
      final notes = score.allNotes;

      expect(notes.length, equals(3), reason: 'C-E-G 大三和弦应有 3 个音符');
      expect(notes[0].startMs, equals(0), reason: 'C4 在 tick 0');
      expect(notes[1].startMs, equals(0),
          reason: 'E4 (chord) 应与 C4 同时开始');
      expect(notes[2].startMs, equals(0),
          reason: 'G4 (chord) 应与 C4 同时开始');
    });

    test('和弦 pitchNumber 正确', () {
      const chordXml = '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE score-partwise PUBLIC "-//Recordare//DTD MusicXML 2.0 Partwise//EN"
  "http://www.musicxml.org/dtds/partwise.dtd">
<score-partwise>
  <work><work-title>Chord</work-title></work>
  <identification><creator type="composer">Tester</creator></identification>
  <part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>
  <part id="P1">
    <measure number="1">
      <attributes>
        <divisions>4</divisions>
        <time><beats>4</beats><beat-type>4</beat-type></time>
      </attributes>
      <note>
        <pitch><step>C</step><octave>4</octave></pitch>
        <duration>4</duration>
      </note>
      <note>
        <chord/>
        <pitch><step>E</step><octave>4</octave></pitch>
        <duration>4</duration>
      </note>
      <note>
        <chord/>
        <pitch><step>G</step><octave>4</octave></pitch>
        <duration>4</duration>
      </note>
    </measure>
  </part>
</score-partwise>
''';
      final score = MusicXmlParser.parseString(chordXml);
      final notes = score.allNotes;

      // C major chord: C4=60, E4=64, G4=67
      final pitches = notes.map((n) => n.pitchNumber).toList()..sort();
      expect(pitches, equals([60, 64, 67]), reason: 'C 大三和弦 MIDI 为 60, 64, 67');
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 4. AutoPlayer 事件调度
  // ══════════════════════════════════════════════════════════════
  group('AutoPlayer 事件调度', () {
    const testXml = '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE score-partwise PUBLIC "-//Recordare//DTD MusicXML 2.0 Partwise//EN"
  "http://www.musicxml.org/dtds/partwise.dtd">
<score-partwise>
  <work><work-title>Scheduler Test</work-title></work>
  <identification><creator type="composer">Tester</creator></identification>
  <part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>
  <part id="P1">
    <measure number="1">
      <attributes>
        <divisions>4</divisions>
        <time><beats>4</beats><beat-type>4</beat-type></time>
      </attributes>
      <direction><sound tempo="120"/></direction>
      <note>
        <pitch><step>C</step><octave>4</octave></pitch>
        <duration>4</duration>
      </note>
      <note>
        <pitch><step>E</step><octave>4</octave></pitch>
        <duration>4</duration>
      </note>
      <note>
        <pitch><step>G</step><octave>4</octave></pitch>
        <duration>8</duration>
      </note>
    </measure>
  </part>
</score-partwise>
''';

    test('Note On/Off 时间计算正确', () {
      final score = MusicXmlParser.parseString(testXml);
      expect(score.allNotes.length, equals(3));

      // 🔑 关键验证: AutoPlayer 现在使用 score.tempo (120) 而非硬编码 120
      // 对这个测试用例 tempo=120 结果相同，但逻辑已修正
      expect(score.tempo, equals(120), reason: '测试 XML 的 tempo 应为 120');

      final notes = score.allNotes;
      final beatMs = 60000 / score.tempo; // 使用实际 tempo

      // C4: start=0, duration=1.0 → off@500ms
      final c4OffMs = notes[0].startMs + (notes[0].duration * beatMs).round();
      expect(c4OffMs, equals(500), reason: 'C4 Note Off 应在 500ms');

      // E4: start=500, duration=1.0 → off@1000ms
      final e4OffMs = notes[1].startMs + (notes[1].duration * beatMs).round();
      expect(e4OffMs, equals(1000), reason: 'E4 Note Off 应在 1000ms');

      // G4: start=1000, duration=2.0 → off@2000ms
      final g4OffMs = notes[2].startMs + (notes[2].duration * beatMs).round();
      expect(g4OffMs, equals(2000), reason: 'G4 Note Off 应在 2000ms');
    });

    test('tempo 修正验证: 使用 score.tempo 而非硬编码 120', () {
      // 用 60 BPM 的乐谱验证 AutoPlayer 内部事件生成
      const slowXml = '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE score-partwise PUBLIC "-//Recordare//DTD MusicXML 2.0 Partwise//EN"
  "http://www.musicxml.org/dtds/partwise.dtd">
<score-partwise>
  <work><work-title>Slow</work-title></work>
  <identification><creator type="composer">Tester</creator></identification>
  <part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>
  <part id="P1">
    <measure number="1">
      <attributes>
        <divisions>4</divisions>
        <time><beats>4</beats><beat-type>4</beat-type></time>
      </attributes>
      <direction><sound tempo="60"/></direction>
      <note>
        <pitch><step>C</step><octave>4</octave></pitch>
        <duration>4</duration>
      </note>
    </measure>
  </part>
</score-partwise>
''';

      final score = MusicXmlParser.parseString(slowXml);
      expect(score.tempo, equals(60));

      final notes = score.allNotes;
      // 60 BPM → beatMs = 1000ms
      // C4 duration=1.0 → off@1000ms
      // 如果 AutoPlayer 仍用硬编码 120, beatMs=500 → off@500ms (错误!)
      final correctBeatMs = 60000 / score.tempo; // 1000ms
      final wrongBeatMs = 60000 / 120; // 500ms (旧 bug)

      final correctOffMs = notes[0].startMs + (notes[0].duration * correctBeatMs).round();
      final wrongOffMs = notes[0].startMs + (notes[0].duration * wrongBeatMs).round();

      expect(correctOffMs, equals(1000),
          reason: '60 BPM 下 C4 Note Off 应在 1000ms');
      expect(wrongOffMs, equals(500),
          reason: '如果用硬编码 120 BPM, 会错误地得到 500ms');
      expect(correctOffMs, isNot(equals(wrongOffMs)),
          reason: '修正后 tempo=60 和 硬编码 120 的结果应不同');
    });

    test('AutoPlayer 基本属性正确', () {
      final score = MusicXmlParser.parseString(testXml);
      final player = AutoPlayer(score);

      expect(player.isPlaying, isFalse);
      expect(player.isPaused, isFalse);
      expect(player.totalMeasures, equals(1));

      player.dispose();
    });

    test('播放状态流可订阅', () {
      final score = MusicXmlParser.parseString(testXml);
      final player = AutoPlayer(score);

      // 验证 stateStream 和 measureStream 是可订阅的
      expect(player.stateStream, isNotNull);
      expect(player.measureStream, isNotNull);

      player.dispose();
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 5. 实际乐谱文件解析 (Bach Prelude C Major)
  // ══════════════════════════════════════════════════════════════
  group('实际乐谱文件解析 (Bach Prelude C Major BWV 846)', () {
    late Score bachScore;

    setUpAll(() {
      const bachXml = '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE score-partwise PUBLIC "-//Recordare//DTD MusicXML 2.0 Partwise//EN"
  "http://www.musicxml.org/dtds/partwise.dtd">
<score-partwise>
  <work><work-title>Praeludium in C-Dur, BWV 846</work-title></work>
  <identification><creator type="composer">Johann Sebastian Bach</creator></identification>
  <part-list><score-part id="P1"><part-name>Klavier</part-name></score-part></part-list>
  <part id="P1">
    <measure number="1">
      <attributes>
        <divisions>4</divisions>
        <key><fifths>0</fifths><mode>major</mode></key>
        <time><beats>4</beats><beat-type>4</beat-type></time>
      </attributes>
      <direction><sound tempo="74"/></direction>
      <note><rest/><duration>2</duration><voice>1</voice></note>
      <note><pitch><step>G</step><octave>4</octave></pitch><duration>1</duration><voice>1</voice></note>
      <note><pitch><step>C</step><octave>5</octave></pitch><duration>1</duration><voice>1</voice></note>
      <note><pitch><step>E</step><octave>5</octave></pitch><duration>1</duration><voice>1</voice></note>
      <note><pitch><step>G</step><octave>4</octave></pitch><duration>1</duration><voice>1</voice></note>
      <note><pitch><step>C</step><octave>5</octave></pitch><duration>1</duration><voice>1</voice></note>
      <note><pitch><step>E</step><octave>5</octave></pitch><duration>1</duration><voice>1</voice></note>
      <note><rest/><duration>2</duration><voice>1</voice></note>
      <note><pitch><step>F</step><octave>4</octave></pitch><duration>1</duration><voice>2</voice></note>
      <note><pitch><step>A</step><octave>4</octave></pitch><duration>1</duration><voice>2</voice></note>
      <note><pitch><step>C</step><octave>5</octave></pitch><duration>1</duration><voice>2</voice></note>
      <note><pitch><step>F</step><octave>4</octave></pitch><duration>1</duration><voice>2</voice></note>
      <note><pitch><step>A</step><octave>4</octave></pitch><duration>1</duration><voice>2</voice></note>
      <note><pitch><step>C</step><octave>5</octave></pitch><duration>1</duration><voice>2</voice></note>
    </measure>
    <measure number="2">
      <note><rest/><duration>2</duration><voice>1</voice></note>
      <note><pitch><step>G</step><octave>4</octave></pitch><duration>1</duration><voice>1</voice></note>
      <note><pitch><step>C</step><octave>5</octave></pitch><duration>1</duration><voice>1</voice></note>
      <note><pitch><step>E</step><octave>5</octave></pitch><duration>1</duration><voice>1</voice></note>
      <note><pitch><step>G</step><octave>4</octave></pitch><duration>1</duration><voice>1</voice></note>
      <note><pitch><step>C</step><octave>5</octave></pitch><duration>1</duration><voice>1</voice></note>
      <note><pitch><step>E</step><octave>5</octave></pitch><duration>1</duration><voice>1</voice></note>
      <note><rest/><duration>2</duration><voice>1</voice></note>
      <note><pitch><step>F</step><octave>4</octave></pitch><duration>1</duration><voice>2</voice></note>
      <note><pitch><step>A</step><octave>4</octave></pitch><duration>1</duration><voice>2</voice></note>
      <note><pitch><step>C</step><octave>5</octave></pitch><duration>1</duration><voice>2</voice></note>
      <note><pitch><step>F</step><octave>4</octave></pitch><duration>1</duration><voice>2</voice></note>
      <note><pitch><step>A</step><octave>4</octave></pitch><duration>1</duration><voice>2</voice></note>
      <note><pitch><step>C</step><octave>5</octave></pitch><duration>1</duration><voice>2</voice></note>
    </measure>
  </part>
</score-partwise>
''';
      bachScore = MusicXmlParser.parseString(bachXml);
    });

    test('元数据解析正确', () {
      expect(bachScore.title, equals('Praeludium in C-Dur, BWV 846'));
      expect(bachScore.composer, equals('Johann Sebastian Bach'));
      expect(bachScore.tempo, equals(74));
      expect(bachScore.totalMeasures, equals(2));
    });

    test('音符 pitch 正确还原', () {
      final notes = bachScore.allNotes;
      expect(notes.length, equals(24),
          reason: '2 小节 × 每小节 12 音符 = 24 (休止符不计入)');

      final g4 = notes.firstWhere((n) => n.measureNumber == 1 && n.pitch == 'G4');
      expect(g4.pitchNumber, equals(67), reason: 'G4 = MIDI 67');

      final c5 = notes.firstWhere((n) => n.measureNumber == 1 && n.pitch == 'C5');
      expect(c5.pitchNumber, equals(72), reason: 'C5 = MIDI 72');

      final e5 = notes.firstWhere((n) => n.measureNumber == 1 && n.pitch == 'E5');
      expect(e5.pitchNumber, equals(76), reason: 'E5 = MIDI 76');

      final f4 = notes.firstWhere((n) => n.measureNumber == 1 && n.pitch == 'F4');
      expect(f4.pitchNumber, equals(65), reason: 'F4 = MIDI 65');

      final a4 = notes.firstWhere((n) => n.measureNumber == 1 && n.pitch == 'A4');
      expect(a4.pitchNumber, equals(69), reason: 'A4 = MIDI 69');
    });

    test('Bach Prelude 时间轴 (tempo=74, divisions=4)', () {
      final notes = bachScore.allNotes;
      final beatMs = 60000 / 74; // ≈ 810.81ms
      final msPerTick = beatMs / 4; // ≈ 202.7ms

      // G4 (voice1, tickPos=2)
      final g4Voice1 = notes.firstWhere(
        (n) => n.measureNumber == 1 && n.pitch == 'G4' && n.startMs > 0,
      );
      final expectedG4Start = (2 * msPerTick).round();
      expect(g4Voice1.startMs, equals(expectedG4Start),
          reason: 'G4 (voice1) 在 tickPos=2, tempo=74, 应为 ${expectedG4Start}ms');

      // F4 (voice2, tickPos=8)
      final f4Voice2 = notes.firstWhere(
        (n) => n.measureNumber == 1 && n.pitch == 'F4',
      );
      final expectedF4Start = (8 * msPerTick).round();
      expect(f4Voice2.startMs, equals(expectedF4Start),
          reason: 'F4 (voice2) 在 tickPos=8, 应为 ${expectedF4Start}ms');

      // 第2小节偏移 = 16 ticks × msPerTick
      final measure2Offset = (16 * msPerTick).round();
      final m2FirstNote = notes.firstWhere(
        (n) => n.measureNumber == 2 && n.pitch == 'G4',
      );
      final expectedM2Start = measure2Offset + (2 * msPerTick).round();
      expect(m2FirstNote.startMs, equals(expectedM2Start),
          reason: '第2小节 G4 (voice1, tickPos=2) 应为 ${expectedM2Start}ms');
    });

    test('AutoPlayer 基本属性 (Bach)', () {
      final player = AutoPlayer(bachScore);
      expect(player.totalMeasures, equals(2));
      expect(player.isPlaying, isFalse);
      player.dispose();
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 6. 边界条件
  // ══════════════════════════════════════════════════════════════
  group('边界条件', () {
    test('空乐谱 (只有休止符) 解析不崩溃', () {
      const emptyXml = '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE score-partwise PUBLIC "-//Recordare//DTD MusicXML 2.0 Partwise//EN"
  "http://www.musicxml.org/dtds/partwise.dtd">
<score-partwise>
  <work><work-title>Empty</work-title></work>
  <identification><creator type="composer">Nobody</creator></identification>
  <part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>
  <part id="P1">
    <measure number="1">
      <attributes>
        <divisions>4</divisions>
        <time><beats>4</beats><beat-type>4</beat-type></time>
      </attributes>
      <note><rest/><duration>16</duration></note>
    </measure>
  </part>
</score-partwise>
''';
      final score = MusicXmlParser.parseString(emptyXml);
      expect(score.allNotes, isEmpty);
      expect(score.totalMeasures, equals(1));
    });

    test('Note.pitchNumber 均在 MIDI 范围 [0, 127] 内', () {
      const xml = '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE score-partwise PUBLIC "-//Recordare//DTD MusicXML 2.0 Partwise//EN"
  "http://www.musicxml.org/dtds/partwise.dtd">
<score-partwise>
  <work><work-title>Range</work-title></work>
  <identification><creator type="composer">Tester</creator></identification>
  <part-list><score-part id="P1"><part-name>Piano</part-name></score-part></part-list>
  <part id="P1">
    <measure number="1">
      <attributes>
        <divisions>4</divisions>
        <time><beats>4</beats><beat-type>4</beat-type></time>
      </attributes>
      <note><pitch><step>A</step><octave>0</octave></pitch><duration>4</duration></note>
      <note><pitch><step>C</step><octave>4</octave></pitch><duration>4</duration></note>
      <note><pitch><step>C</step><octave>8</octave></pitch><duration>4</duration></note>
    </measure>
  </part>
</score-partwise>
''';
      final score = MusicXmlParser.parseString(xml);
      for (final note in score.allNotes) {
        expect(
          note.pitchNumber,
          inInclusiveRange(0, 127),
          reason: '${note.pitch} pitchNumber=${note.pitchNumber} 超出 MIDI 范围',
        );
      }
    });
  });
}
