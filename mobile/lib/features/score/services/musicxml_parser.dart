import 'dart:io';
import 'package:xml/xml.dart';
import '../models/score.dart';

/// MusicXML 解析器
///
/// 支持 MusicXML 3.1 score-partwise 格式
/// - 元数据提取 (标题/作曲家/tempo)
/// - divisions/拍号/调号 (支持中途变更)
/// - 音符解析 (pitch/duration/rest/chord)
/// - 正确处理 <backup> / <forward> 元素
/// - 时间轴计算基于逐小节累加 (支持变拍号)
class MusicXmlParser {
  /// 解析 MusicXML 文件
  static Future<Score> parseFile(String filePath, {String? scoreId}) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw MusicXmlParseException('文件不存在: $filePath');
    }
    final content = await file.readAsString();
    return parseString(content, filePath: filePath, scoreId: scoreId);
  }

  /// 解析 MusicXML 字符串
  static Score parseString(String xmlContent, {String? filePath, String? scoreId}) {
    try {
      final document = XmlDocument.parse(xmlContent);

      // 支持 score-partwise 和 score-timewise
      XmlElement? scoreElement = document.getElement('score-partwise');
      bool isPartwise = true;
      if (scoreElement == null) {
        scoreElement = document.getElement('score-timewise');
        isPartwise = false;
      }
      if (scoreElement == null) {
        throw MusicXmlParseException('不支持的 MusicXML 格式 (需要 score-partwise 或 score-timewise)');
      }

      final metadata = _parseMetadata(scoreElement);
      final partList = _parsePartList(scoreElement);
      final parts = _parseParts(scoreElement, partList, isPartwise);

      int totalMeasures = 0;
      for (final part in parts) {
        if (part.measures.length > totalMeasures) {
          totalMeasures = part.measures.length;
        }
      }

      final allNotes = <Note>[];
      for (final part in parts) {
        for (final measure in part.measures) {
          allNotes.addAll(measure.notes);
        }
      }
      allNotes.sort((a, b) => a.startMs.compareTo(b.startMs));

      return Score(
        id: scoreId ?? DateTime.now().millisecondsSinceEpoch.toString(),
        title: metadata.title,
        composer: metadata.composer,
        difficulty: _guessDifficulty(allNotes, metadata.tempo),
        parts: parts,
        totalMeasures: totalMeasures,
        estimatedDuration: _estimateDuration(allNotes, metadata.tempo),
        musicXmlPath: filePath ?? '',
        tags: [],
      );
    } on MusicXmlParseException {
      rethrow;
    } catch (e) {
      throw MusicXmlParseException('解析失败: $e');
    }
  }

  // ────────────────────────────── 元数据 ──────────────────────────────

  static _ScoreMetadata _parseMetadata(XmlElement scoreElement) {
    String title = '未知曲目';
    String composer = '未知作曲家';
    int tempo = 120;

    // 标题: work → work-title
    final workTitle = scoreElement
        .getElement('work')
        ?.getElement('work-title');
    if (workTitle != null) {
      title = workTitle.innerText.trim();
    }

    // movement-title 备选
    if (title == '未知曲目') {
      final movementTitle = scoreElement.getElement('movement-title');
      if (movementTitle != null) {
        title = movementTitle.innerText.trim();
      }
    }

    // 作曲家: identification → creator[@type='composer']
    final identification = scoreElement.getElement('identification');
    if (identification != null) {
      for (final creator in identification.findElements('creator')) {
        final type = creator.getAttribute('type') ?? '';
        if (type == 'composer' || type == 'lyricist') {
          composer = creator.innerText.trim();
          break;
        }
      }
    }

    // 备选标题: credit → credit-words
    if (title == '未知曲目') {
      for (final credit in scoreElement.findElements('credit')) {
        for (final words in credit.findElements('credit-words')) {
          final text = words.innerText.trim();
          if (text.isNotEmpty && text.length < 100) {
            title = text;
            break;
          }
        }
        if (title != '未知曲目') break;
      }
    }

    // 速度: 第一个 part 第一个 measure
    final firstPart = scoreElement.getElement('part');
    if (firstPart != null) {
      final firstMeasure = firstPart.getElement('measure');
      if (firstMeasure != null) {
        for (final sound in firstMeasure.findElements('sound')) {
          final tempoAttr = sound.getAttribute('tempo');
          if (tempoAttr != null) {
            tempo = int.tryParse(tempoAttr) ?? tempo;
            break;
          }
        }
        if (tempo == 120) {
          for (final dir in firstMeasure.findElements('direction')) {
            final dirType = dir.getElement('direction-type');
            if (dirType != null) {
              final perMin = dirType
                  .getElement('metronome')
                  ?.getElement('per-minute');
              if (perMin != null) {
                tempo = int.tryParse(perMin.innerText) ?? tempo;
                break;
              }
            }
          }
        }
      }
    }

    return _ScoreMetadata(title: title, composer: composer, tempo: tempo);
  }

  // ────────────────────────────── 声部列表 ──────────────────────────────

  static Map<String, _PartDef> _parsePartList(XmlElement scoreElement) {
    final result = <String, _PartDef>{};
    final partListEl = scoreElement.getElement('part-list');
    if (partListEl == null) return result;

    for (final sp in partListEl.findElements('score-part')) {
      final id = sp.getAttribute('id') ?? '';
      final name = sp.getElement('part-name')?.innerText.trim() ?? 'Piano';
      result[id] = _PartDef(id: id, name: name);
    }
    return result;
  }

  // ────────────────────────────── 声部解析 ──────────────────────────────

  static List<Part> _parseParts(
    XmlElement scoreElement,
    Map<String, _PartDef> partList,
    bool isPartwise,
  ) {
    final parts = <Part>[];

    for (final partEl in scoreElement.findElements('part')) {
      final partId = partEl.getAttribute('id') ?? 'P1';
      final partDef = partList[partId] ?? _PartDef(id: partId, name: 'Piano');

      int divisions = 4;
      TimeSignature timeSig = TimeSignature.common;
      KeySignature keySig = KeySignature.cMajor;
      int tempo = 120;

      final measures = <Measure>[];
      int cumulativeMs = 0;

      for (final measureEl in partEl.findElements('measure')) {
        final measureNumber =
            int.tryParse(measureEl.getAttribute('number') ?? '') ??
            (measures.length + 1);

        // ── attributes (拍号/调号/divisions) ──
        final attrs = measureEl.getElement('attributes');
        if (attrs != null) {
          final divEl = attrs.getElement('divisions');
          if (divEl != null) {
            divisions = int.tryParse(divEl.innerText) ?? divisions;
          }

          final timeEl = attrs.getElement('time');
          if (timeEl != null) {
            final beats =
                int.tryParse(timeEl.getElement('beats')?.innerText ?? '4') ?? 4;
            final beatType =
                int.tryParse(timeEl.getElement('beat-type')?.innerText ?? '4') ??
                4;
            timeSig = TimeSignature(beats: beats, beatType: beatType);
          }

          final keyEl = attrs.getElement('key');
          if (keyEl != null) {
            final fifths =
                int.tryParse(keyEl.getElement('fifths')?.innerText ?? '0') ?? 0;
            final mode = keyEl.getElement('mode')?.innerText ?? 'major';
            keySig = KeySignature(fifths: fifths, mode: mode);
          }
        }

        // ── 速度变更 ──
        for (final dir in measureEl.findElements('direction')) {
          final sound = dir.getElement('sound');
          if (sound != null) {
            final t = sound.getAttribute('tempo');
            if (t != null) tempo = int.tryParse(t) ?? tempo;
          }
        }

        // ── 解析音符 ──
        final notes = <Note>[];
        int tickPos = 0;

        for (final child in measureEl.children) {
          if (child is! XmlElement) continue;
          final tag = child.name.local;

          if (tag == 'note') {
            final chord = child.getElement('chord') != null;

            final note = _parseNote(
              child,
              measureNumber: measureNumber,
              divisions: divisions,
              tempo: tempo,
              measureStartMs: cumulativeMs,
              tickPos: chord ? tickPos : tickPos,
            );

            if (note != null) notes.add(note);

            // 非和弦音符才推进 tick
            if (!chord) {
              final dur = child.getElement('duration');
              if (dur != null) {
                tickPos += int.tryParse(dur.innerText) ?? divisions;
              } else {
                tickPos += divisions;
              }
            }
          } else if (tag == 'forward') {
            final dur = child.getElement('duration');
            if (dur != null) {
              tickPos += int.tryParse(dur.innerText) ?? divisions;
            }
          } else if (tag == 'backup') {
            final dur = child.getElement('duration');
            if (dur != null) {
              tickPos -= int.tryParse(dur.innerText) ?? divisions;
              if (tickPos < 0) tickPos = 0;
            }
          }
        }

        measures.add(Measure(
          number: measureNumber,
          notes: notes,
          timeSignature: timeSig,
          keySignature: keySig,
        ));

        // 累计时间 — 基于当前小节的 divisions 和拍号
        final ticksPerMeasure =
            timeSig.beats * (4 ~/ timeSig.beatType) * divisions;
        final msPerTick = 60000.0 / (tempo * divisions);
        cumulativeMs += (ticksPerMeasure * msPerTick).round();
      }

      parts.add(Part(name: partDef.name, measures: measures));
    }

    return parts;
  }

  // ────────────────────────────── 单音符解析 ──────────────────────────────

  static Note? _parseNote(
    XmlNode noteEl, {
    required int measureNumber,
    required int divisions,
    required int tempo,
    required int measureStartMs,
    required int tickPos,
  }) {
    // 休止符 → 跳过
    if (noteEl.getElement('rest') != null) return null;

    // 音高
    final pitchEl = noteEl.getElement('pitch');
    if (pitchEl == null) return null;

    final step = pitchEl.getElement('step')?.innerText ?? 'C';
    final alter =
        int.tryParse(pitchEl.getElement('alter')?.innerText ?? '0') ?? 0;
    final octave =
        int.tryParse(pitchEl.getElement('octave')?.innerText ?? '4') ?? 4;

    // MIDI pitchNumber
    const stepIndex = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11};
    final pitchNumber = (octave + 1) * 12 + (stepIndex[step] ?? 0) + alter;

    // 时值
    final durTicks =
        int.tryParse(noteEl.getElement('duration')?.innerText ?? '') ??
        divisions;
    final duration = durTicks / divisions;

    // 开始时间 (ms)
    final msPerTick = 60000.0 / (tempo * divisions);
    final startMs = measureStartMs + (tickPos * msPerTick).round();

    // 音符名称
    final pitchName = _buildPitchName(step, alter, octave);

    return Note(
      pitch: pitchName,
      pitchNumber: pitchNumber,
      duration: duration,
      startMs: startMs,
      measureNumber: measureNumber,
    );
  }

  static String _buildPitchName(String step, int alter, int octave) {
    final buf = StringBuffer(step);
    if (alter > 0) {
      for (int i = 0; i < alter; i++) buf.write('#');
    } else if (alter < 0) {
      for (int i = 0; i < -alter; i++) buf.write('b');
    }
    buf.write(octave);
    return buf.toString();
  }

  // ────────────────────────────── 工具方法 ──────────────────────────────

  static Duration _estimateDuration(List<Note> notes, int tempo) {
    if (notes.isEmpty) return Duration.zero;
    final last = notes.last;
    final beatMs = 60000 / tempo;
    final totalMs = last.startMs + (last.duration * beatMs).round();
    return Duration(milliseconds: totalMs);
  }

  static String _guessDifficulty(List<Note> notes, int tempo) {
    if (notes.isEmpty) return 'beginner';

    int minP = 127, maxP = 0;
    for (final n in notes) {
      if (n.pitchNumber < minP) minP = n.pitchNumber;
      if (n.pitchNumber > maxP) maxP = n.pitchNumber;
    }

    final range = maxP - minP;
    if (range > 48 || tempo > 140) return 'advanced';
    if (range > 30 || tempo > 120) return 'intermediate';
    return 'beginner';
  }
}

// ────────────────────────────── 内部类型 ──────────────────────────────

class _ScoreMetadata {
  final String title;
  final String composer;
  final int tempo;
  _ScoreMetadata({required this.title, required this.composer, required this.tempo});
}

class _PartDef {
  final String id;
  final String name;
  _PartDef({required this.id, required this.name});
}

class MusicXmlParseException implements Exception {
  final String message;
  MusicXmlParseException(this.message);
  @override
  String toString() => 'MusicXmlParseException: $message';
}
