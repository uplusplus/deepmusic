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
        tempo: metadata.tempo,
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
        // 优先: <direction><sound tempo="..."/></direction>
        for (final dir in firstMeasure.findElements('direction')) {
          final sound = dir.getElement('sound');
          if (sound != null) {
            final t = sound.getAttribute('tempo');
            if (t != null) {
              tempo = int.tryParse(t) ?? tempo;
              break;
            }
          }
        }
        // 备选: <sound tempo="..."/> 作为 measure 直接子元素
        if (tempo == 120) {
          for (final sound in firstMeasure.findElements('sound')) {
            final tempoAttr = sound.getAttribute('tempo');
            if (tempoAttr != null) {
              tempo = int.tryParse(tempoAttr) ?? tempo;
              break;
            }
          }
        }
        // 备选: <metronome><per-minute>
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

    // ── 第一遍：解析第一个声部，建立参考时间轴 ──
    // 多声部曲目各声部应共享同一 tempo 和时间轴
    final refMeasureStartMs = <int, int>{}; // {measureNumber: absoluteMs}
    final refTempo = <int, int>{}; // {measureNumber: startTempo}
    {
      int rDivs = 4;
      TimeSignature rTs = TimeSignature.common;
      int rTempo = 120;
      int rCumMs = 0;
      final firstPart = scoreElement.findElements('part').firstOrNull;
      if (firstPart != null) {
        for (final mEl in firstPart.findElements('measure')) {
          final mNum = int.tryParse(mEl.getAttribute('number') ?? '') ?? 0;
          final a = mEl.getElement('attributes');
          if (a != null) {
            final d = a.getElement('divisions');
            if (d != null) rDivs = int.tryParse(d.innerText) ?? rDivs;
            final t = a.getElement('time');
            if (t != null) {
              final b = int.tryParse(t.getElement('beats')?.innerText ?? '4') ?? 4;
              final bt = int.tryParse(t.getElement('beat-type')?.innerText ?? '4') ?? 4;
              rTs = TimeSignature(beats: b, beatType: bt);
            }
          }
          final mStartTempo = rTempo;
          refMeasureStartMs[mNum] = rCumMs;
          refTempo[mNum] = mStartTempo;
          // 提取 tempo 变更（支持 offset）
          final measureStartTempoRef = rTempo;
          final refTempoChanges = <int, int>{};
          for (final dir in mEl.findElements('direction')) {
            final snd = dir.getElement('sound');
            if (snd != null) {
              final t = snd.getAttribute('tempo');
              if (t != null) {
                final newT = int.tryParse(t) ?? rTempo;
                final offsetEl = dir.getElement('offset');
                int offsetTick = 0;
                if (offsetEl != null) {
                  offsetTick = int.tryParse(offsetEl.innerText) ?? 0;
                }
                refTempoChanges[offsetTick] = newT;
                rTempo = newT;
              }
            }
          }
          for (final snd in mEl.findAllElements('sound')) {
            if (snd.parent is XmlElement &&
                (snd.parent as XmlElement).name.local == 'direction') continue;
            final t = snd.getAttribute('tempo');
            if (t != null) {
              final newT = int.tryParse(t) ?? rTempo;
              refTempoChanges[0] = newT;
              rTempo = newT;
            }
          }

          final tpm = (rTs.beats * 4 / rTs.beatType * rDivs).round();
          if (refTempoChanges.isEmpty) {
            final mpt = 60000.0 / (measureStartTempoRef * rDivs);
            rCumMs += (tpm * mpt).round();
          } else {
            final sortedOffsets = refTempoChanges.keys.toList()..sort();
            int segStart = 0;
            int segTempo = measureStartTempoRef;
            for (final offset in sortedOffsets) {
              final segLen = offset - segStart;
              if (segLen > 0) {
                final mpt = 60000.0 / (segTempo * rDivs);
                rCumMs += (segLen * mpt).round();
              }
              segStart = offset;
              segTempo = refTempoChanges[offset]!;
            }
            final remaining = tpm - segStart;
            if (remaining > 0) {
              final mpt = 60000.0 / (segTempo * rDivs);
              rCumMs += (remaining * mpt).round();
            }
          }
        }
      }
    }

    for (final partEl in scoreElement.findElements('part')) {
      final partId = partEl.getAttribute('id') ?? 'P1';
      final partDef = partList[partId] ?? _PartDef(id: partId, name: 'Piano');

      int divisions = 4;
      TimeSignature timeSig = TimeSignature.common;
      KeySignature keySig = KeySignature.cMajor;
      int tempo = 120;

      final measures = <Measure>[];

      for (final measureEl in partEl.findElements('measure')) {
        final measureNumber =
            int.tryParse(measureEl.getAttribute('number') ?? '') ??
            (measures.length + 1);

        // 使用第一个声部的时间轴（所有声部共享）
        final int cumulativeMs = refMeasureStartMs[measureNumber] ?? 0;
        tempo = refTempo[measureNumber] ?? tempo; // 使用参考 tempo

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

        // ── 速度变更 (支持 <sound tempo="..."/> 在 <direction> 内或作为 measure 直接子元素) ──
        for (final dir in measureEl.findElements('direction')) {
          final sound = dir.getElement('sound');
          if (sound != null) {
            final t = sound.getAttribute('tempo');
            if (t != null) tempo = int.tryParse(t) ?? tempo;
          }
        }
        for (final sound in measureEl.findElements('sound')) {
          // 跳过已在 direction 内处理过的 sound
          if (sound.parent is XmlElement &&
              (sound.parent as XmlElement).name.local == 'direction') continue;
          final t = sound.getAttribute('tempo');
          if (t != null) tempo = int.tryParse(t) ?? tempo;
        }

        // ── 解析音符 ──
        final notes = <Note>[];
        int tickPos = 0;
        int prevNoteTickPos = 0;

        // 每小节初始化：调号默认升降号 + 小节内临时记号追踪
        final measureAccidentals = Map<String, int>.from(
          _getKeyAlterations(keySig.fifths),
        );

        for (final child in measureEl.children) {
          if (child is! XmlElement) continue;
          final tag = child.name.local;

          if (tag == 'note') {
            final chord = child.getElement('chord') != null;
            final effectiveTickPos = chord ? prevNoteTickPos : tickPos;

            // ── 升降号解析优先级 ──
            // 1. <pitch><alter> (显式, 最高优先级)
            // 2. <accidental> (显示记号, 影响演奏)
            // 3. 小节内同音名之前的临时记号 / 调号默认
            final step = child
                .getElement('pitch')
                ?.getElement('step')
                ?.innerText ?? '';
            int resolvedAlter = 0;

            if (step.isNotEmpty) {
              final alterEl = child.getElement('pitch')?.getElement('alter');
              final accidentalEl = child.getElement('accidental');

              if (alterEl != null) {
                resolvedAlter = int.tryParse(alterEl.innerText) ?? 0;
              } else if (accidentalEl != null) {
                resolvedAlter = _alterFromAccidental(accidentalEl.innerText.trim());
              } else {
                resolvedAlter = measureAccidentals[step] ?? 0;
              }

              // 显式出现 alter 或 accidental → 更新小节追踪
              if (alterEl != null || accidentalEl != null) {
                measureAccidentals[step] = resolvedAlter;
              }
            }

            final note = _parseNote(
              child,
              measureNumber: measureNumber,
              divisions: divisions,
              tempo: tempo,
              measureStartMs: cumulativeMs,
              tickPos: effectiveTickPos,
              resolvedAlter: resolvedAlter,
            );

            if (note != null) notes.add(note);

            if (!chord) {
              prevNoteTickPos = tickPos;
              final dur = child.getElement('duration');
              if (dur != null) {
                tickPos += int.tryParse(dur.innerText) ?? divisions;
              } else {
                tickPos += divisions;
              }
            }
          } else if (tag == 'attributes') {
            // 小节中间的属性变更 (如中途转调)
            final keyEl = child.getElement('key');
            if (keyEl != null) {
              final fifths =
                  int.tryParse(keyEl.getElement('fifths')?.innerText ?? '0') ?? 0;
              keySig = KeySignature(
                fifths: fifths,
                mode: keyEl.getElement('mode')?.innerText ?? 'major',
              );
              measureAccidentals
                ..clear()
                ..addAll(_getKeyAlterations(fifths));
            }
          } else if (tag == 'forward') {
            prevNoteTickPos = tickPos;
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
            prevNoteTickPos = tickPos;
          }
        }

        measures.add(Measure(
          number: measureNumber,
          notes: notes,
          timeSignature: timeSig,
          keySignature: keySig,
        ));

        // 累计时间 — 使用参考时间轴，不需要本地计算
        // (refMeasureStartMs 已由第一遍解析提供)
      }

      parts.add(Part(name: partDef.name, measures: measures));
    }

    return parts;
  }

  // ────────────────────────────── 辅助：调号和临时记号处理 ──────────────────────────────

  /// 根据调号的 fifths 值返回每个音名的默认升降号
  static Map<String, int> _getKeyAlterations(int fifths) {
    const sharpOrder = ['F', 'C', 'G', 'D', 'A', 'E', 'B'];
    const flatOrder = ['B', 'E', 'A', 'D', 'G', 'C', 'F'];
    final alterations = <String, int>{
      'C': 0, 'D': 0, 'E': 0, 'F': 0, 'G': 0, 'A': 0, 'B': 0,
    };
    if (fifths > 0) {
      for (int i = 0; i < fifths && i < sharpOrder.length; i++) {
        alterations[sharpOrder[i]] = 1;
      }
    } else if (fifths < 0) {
      for (int i = 0; i < -fifths && i < flatOrder.length; i++) {
        alterations[flatOrder[i]] = -1;
      }
    }
    return alterations;
  }

  /// 将 <accidental> 文本映射为 alter 值
  static int _alterFromAccidental(String accidental) {
    switch (accidental) {
      case 'sharp': return 1;
      case 'flat': return -1;
      case 'natural': return 0;
      case 'double-sharp':
      case 'sharp-sharp': return 2;
      case 'flat-flat': return -2;
      case 'natural-sharp': return 1;
      case 'natural-flat': return -1;
      case 'quarter-sharp': return 1;
      case 'quarter-flat': return -1;
      case 'three-quarters-sharp': return 1;
      case 'three-quarters-flat': return -1;
      default: return 0;
    }
  }



  static Note? _parseNote(
    XmlNode noteEl, {
    required int measureNumber,
    required int divisions,
    required int tempo,
    required int measureStartMs,
    required int tickPos,
    required int resolvedAlter,
    int defaultStaff = 0,
  }) {
    // 休止符 → 跳过
    if (noteEl.getElement('rest') != null) return null;

    // 音高
    final pitchEl = noteEl.getElement('pitch');
    if (pitchEl == null) return null;

    final step = pitchEl.getElement('step')?.innerText ?? 'C';
    final octave =
        int.tryParse(pitchEl.getElement('octave')?.innerText ?? '4') ?? 4;

    // MIDI pitchNumber — 使用调用方解析好的 alter (已考虑调号+临时记号)
    const stepIndex = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11};
    final pitchNumber = (octave + 1) * 12 + (stepIndex[step] ?? 0) + resolvedAlter;

    // 时值
    final durTicks =
        int.tryParse(noteEl.getElement('duration')?.innerText ?? '') ??
        divisions;
    final duration = durTicks / divisions;

    // 开始时间 (ms) — 使用当前小节的 tempo
    final msPerTick = 60000.0 / (tempo * divisions);
    final startMs = measureStartMs + (tickPos * msPerTick).round();
    // 实际毫秒时长（已考虑所在小节的 tempo）
    final durationMs = (durTicks * msPerTick).round();

    // 谱表
    int staff = defaultStaff;
    final staffEl = noteEl.getElement('staff');
    if (staffEl != null) {
      staff = int.tryParse(staffEl.innerText) ?? defaultStaff;
    }

    // 音符名称
    final pitchName = _buildPitchName(step, resolvedAlter, octave);

    // 力度
    int velocity = 80;
    final velEl = noteEl.getElement('velocity');
    if (velEl != null) {
      velocity = int.tryParse(velEl.innerText) ?? velocity;
    }
    final noteVelAttr = noteEl.getAttribute('dynamics');
    if (noteVelAttr != null) {
      velocity = int.tryParse(noteVelAttr) ?? velocity;
    }

    return Note(
      pitch: pitchName,
      pitchNumber: pitchNumber,
      duration: duration,
      durationMs: durationMs,
      startMs: startMs,
      measureNumber: measureNumber,
      staff: staff,
      velocity: velocity,
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
    // 使用解析器已计算的 durationMs（已按各小节 tempo 正确计算）
    final totalMs = last.startMs + last.durationMs;
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
