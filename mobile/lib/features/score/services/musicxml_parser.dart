import 'dart:io';
import 'package:xml/xml.dart';
import '../models/score.dart';

/// MusicXML 解析器
/// 
/// 支持 MusicXML 3.1 格式，解析为 Score 模型
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
      final scorePartwise = document.getElement('score-partwise');
      final scoreTimewise = document.getElement('score-timewise');

      if (scorePartwise == null && scoreTimewise == null) {
        throw MusicXmlParseException('不是有效的 MusicXML 文件');
      }

      // 优先使用 score-partwise 格式
      final scoreElement = scorePartwise ?? scoreTimewise!;

      // 解析元数据
      final metadata = _parseMetadata(scoreElement);
      
      // 解析声部定义
      final partList = _parsePartList(scoreElement);
      
      // 解析各声部的小节
      final parts = _parseParts(scoreElement, partList);

      // 收集所有音符用于统计
      final allNotes = <Note>[];
      for (final part in parts) {
        for (final measure in part.measures) {
          allNotes.addAll(measure.notes);
        }
      }
      allNotes.sort((a, b) => a.startMs.compareTo(b.startMs));

      // 计算总小节数
      int totalMeasures = 0;
      for (final part in parts) {
        if (part.measures.length > totalMeasures) {
          totalMeasures = part.measures.length;
        }
      }

      // 估算时长
      final estimatedDuration = _estimateDuration(allNotes, metadata.tempo);

      return Score(
        id: scoreId ?? DateTime.now().millisecondsSinceEpoch.toString(),
        title: metadata.title,
        composer: metadata.composer,
        difficulty: _guessDifficulty(allNotes, metadata.tempo),
        parts: parts,
        totalMeasures: totalMeasures,
        estimatedDuration: estimatedDuration,
        musicXmlPath: filePath ?? '',
        tags: [metadata.category].whereType<String>().toList(),
      );
    } catch (e) {
      if (e is MusicXmlParseException) rethrow;
      throw MusicXmlParseException('解析失败: $e');
    }
  }

  /// 解析乐谱元数据
  static _ScoreMetadata _parseMetadata(XmlElement scoreElement) {
    String title = '未知曲目';
    String composer = '未知作曲家';
    int tempo = 120;
    String? category;

    // 解析标题
    final workElement = scoreElement.getElement('work');
    if (workElement != null) {
      final workTitle = workElement.getElement('work-title');
      if (workTitle != null) {
        title = workTitle.innerText.trim();
      }
    }

    // 从 identification 解析
    final identification = scoreElement.getElement('identification');
    if (identification != null) {
      final creatorElements = identification.findElements('creator');
      for (final creator in creatorElements) {
        final type = creator.getAttribute('type');
        if (type == 'composer' || composer == '未知作曲家') {
          composer = creator.innerText.trim();
        }
      }
    }

    // 从 credit 解析备选标题
    if (title == '未知曲目') {
      final credits = scoreElement.findElements('credit');
      for (final credit in credits) {
        final words = credit.findElements('credit-words');
        if (words.isNotEmpty) {
          final text = words.first.innerText.trim();
          if (text.isNotEmpty && text.length < 100) {
            title = text;
            break;
          }
        }
      }
    }

    // 从第一个 part 的第一个 measure 的 direction 解析 tempo
    final firstPart = scoreElement.getElement('part');
    if (firstPart != null) {
      final firstMeasure = firstPart.getElement('measure');
      if (firstMeasure != null) {
        final directions = firstMeasure.findElements('direction');
        for (final direction in directions) {
          final dirType = direction.getElement('direction-type');
          if (dirType != null) {
            final metronome = dirType.getElement('metronome');
            if (metronome != null) {
              final perMinute = metronome.getElement('per-minute');
              if (perMinute != null) {
                tempo = int.tryParse(perMinute.innerText) ?? tempo;
              }
            }
            final tempoElement = dirType.getElement('metronome');
            // 也尝试从 sound 元素获取
          }
        }
        // 从 sound 元素获取 tempo
        final sounds = firstMeasure.findElements('sound');
        for (final sound in sounds) {
          final tempoAttr = sound.getAttribute('tempo');
          if (tempoAttr != null) {
            tempo = int.tryParse(tempoAttr) ?? tempo;
          }
        }
      }
    }

    return _ScoreMetadata(
      title: title,
      composer: composer,
      tempo: tempo,
      category: category,
    );
  }

  /// 解析声部列表
  static Map<String, _PartDef> _parsePartList(XmlElement scoreElement) {
    final partList = <String, _PartDef>{};
    final partListElement = scoreElement.getElement('part-list');
    
    if (partListElement == null) return partList;

    for (final scorePart in partListElement.findElements('score-part')) {
      final id = scorePart.getAttribute('id') ?? '';
      String name = 'Piano';
      
      final partNameElement = scorePart.getElement('part-name');
      if (partNameElement != null) {
        name = partNameElement.innerText.trim();
      }

      // 解析乐器
      String? instrument;
      final midiInstrument = scorePart.getElement('midi-instrument');
      if (midiInstrument != null) {
        final instrName = midiInstrument.getElement('instrument-name');
        if (instrName != null) {
          instrument = instrName.innerText.trim();
        }
      }

      partList[id] = _PartDef(id: id, name: name, instrument: instrument);
    }

    return partList;
  }

  /// 解析所有声部
  static List<Part> _parseParts(XmlElement scoreElement, Map<String, _PartDef> partList) {
    final parts = <Part>[];
    int globalMs = 0; // 全局时间基准

    for (final partElement in scoreElement.findElements('part')) {
      final partId = partElement.getAttribute('id') ?? 'P1';
      final partDef = partList[partId] ?? _PartDef(id: partId, name: 'Piano');
      
      final measures = <Measure>[];
      int partMs = 0; // 声部内时间
      TimeSignature currentTimeSig = TimeSignature.common;
      KeySignature currentKeySig = KeySignature.cMajor;
      int currentTempo = 120;

      for (final measureElement in partElement.findElements('measure')) {
        final measureNumber = int.tryParse(
          measureElement.getAttribute('number') ?? ''
        ) ?? (measures.length + 1);

        final notes = <Note>[];
        final measureStartMs = partMs;

        // 解析属性变更
        final attributes = measureElement.getElement('attributes');
        if (attributes != null) {
          final timeElement = attributes.getElement('time');
          if (timeElement != null) {
            final beats = int.tryParse(
              timeElement.getElement('beats')?.innerText ?? '4'
            ) ?? 4;
            final beatType = int.tryParse(
              timeElement.getElement('beat-type')?.innerText ?? '4'
            ) ?? 4;
            currentTimeSig = TimeSignature(beats: beats, beatType: beatType);
          }

          final keyElement = attributes.getElement('key');
          if (keyElement != null) {
            final fifths = int.tryParse(
              keyElement.getElement('fifths')?.innerText ?? '0'
            ) ?? 0;
            final mode = keyElement.getElement('mode')?.innerText ?? 'major';
            currentKeySig = KeySignature(fifths: fifths, mode: mode);
          }

          final divisions = attributes.getElement('divisions');
          // divisions 表示每四分音符的 tick 数
        }

        // 解析 tempo 变更
        for (final direction in measureElement.findElements('direction')) {
          final sound = direction.getElement('sound');
          if (sound != null) {
            final tempoAttr = sound.getAttribute('tempo');
            if (tempoAttr != null) {
              currentTempo = int.tryParse(tempoAttr) ?? currentTempo;
            }
          }
        }

        // 获取 divisions (默认 4 = 四分音符)
        int divisions = 4;
        if (attributes != null) {
          final divElement = attributes.getElement('divisions');
          if (divElement != null) {
            divisions = int.tryParse(divElement.innerText) ?? 4;
          }
        }

        // 解析音符
        int notePosition = 0; // 当前小节内的 tick 位置
        for (final element in measureElement.childElements) {
          if (element.name.local == 'note') {
            final note = _parseNote(
              element,
              measureNumber: measureNumber,
              divisions: divisions,
              tempo: currentTempo,
              measureStartMs: measureStartMs,
              notePosition: notePosition,
            );
            
            if (note != null) {
              notes.add(note);
              
              // 更新位置 (按 duration tick 前进)
              final durationElement = element.getElement('duration');
              if (durationElement != null) {
                final durationTicks = int.tryParse(durationElement.innerText) ?? divisions;
                notePosition += durationTicks;
              } else {
                notePosition += divisions; // 默认一个四分音符
              }
            }
          } else if (element.name.local == 'forward') {
            // forward 元素：空拍前进
            final durationElement = element.getElement('duration');
            if (durationElement != null) {
              final ticks = int.tryParse(durationElement.innerText) ?? divisions;
              notePosition += ticks;
            }
          } else if (element.name.local == 'backup') {
            // backup 元素：回退 (多声部)
            final durationElement = element.getElement('duration');
            if (durationElement != null) {
              final ticks = int.tryParse(durationElement.innerText) ?? divisions;
              notePosition -= ticks;
              if (notePosition < 0) notePosition = 0;
            }
          }
        }

        // 计算小节总时长
        final beatsPerMeasure = currentTimeSig.beats;
        final beatDuration = 60000 / currentTempo; // 毫秒
        final measureDurationMs = (beatsPerMeasure * beatDuration).toInt();

        measures.add(Measure(
          number: measureNumber,
          notes: notes,
          timeSignature: currentTimeSig,
          keySignature: currentKeySig,
        ));

        partMs = measureStartMs + measureDurationMs;
      }

      parts.add(Part(
        name: partDef.name,
        measures: measures,
      ));
    }

    return parts;
  }

  /// 解析单个音符
  static Note? _parseNote(
    XmlNode noteElement, {
    required int measureNumber,
    required int divisions,
    required int tempo,
    required int measureStartMs,
    required int notePosition,
  }) {
    // 检查是否是休止符
    final rest = noteElement.getElement('rest');
    if (rest != null) return null;

    // 解析音高
    final pitchElement = noteElement.getElement('pitch');
    if (pitchElement == null) return null;

    final step = pitchElement.getElement('step')?.innerText ?? 'C';
    final alter = int.tryParse(pitchElement.getElement('alter')?.innerText ?? '0') ?? 0;
    final octave = int.tryParse(pitchElement.getElement('octave')?.innerText ?? '4') ?? 4;

    // 计算 MIDI 音符号
    const stepToSemitone = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11};
    final baseSemitone = stepToSemitone[step] ?? 0;
    final pitchNumber = (octave + 1) * 12 + baseSemitone + alter;

    // 计算时值
    final durationElement = noteElement.getElement('duration');
    final durationTicks = durationElement != null
        ? int.tryParse(durationElement.innerText) ?? divisions
        : divisions;
    final duration = durationTicks / divisions; // 以四分音符为单位

    // 计算开始时间
    final beatDuration = 60000 / tempo;
    final tickDuration = beatDuration / divisions;
    final startMs = measureStartMs + (notePosition * tickDuration).toInt();

    // 解析音符名称
    String pitchName = step;
    if (alter > 0) {
      pitchName += '#' * alter;
    } else if (alter < 0) {
      pitchName += 'b' * (-alter);
    }
    pitchName += octave.toString();

    // 解析力度
    final dynamics = noteElement.parentElement
        ?.findElements('direction')
        .expand((d) => d.findElements('direction-type'))
        .expand((dt) => dt.findElements('dynamics'))
        .expand((dyn) => dyn.childElements)
        .map((e) => e.name.local)
        .firstOrNull;

    return Note(
      pitch: pitchName,
      pitchNumber: pitchNumber,
      duration: duration,
      startMs: startMs,
      measureNumber: measureNumber,
    );
  }

  /// 估算乐曲时长
  static Duration _estimateDuration(List<Note> notes, int tempo) {
    if (notes.isEmpty) return Duration.zero;
    
    final lastNote = notes.last;
    final beatDuration = 60000 / tempo;
    final noteDurationMs = lastNote.duration * beatDuration;
    final totalMs = lastNote.startMs + noteDurationMs.toInt();
    
    return Duration(milliseconds: totalMs.toInt());
  }

  /// 猜测难度
  static String _guessDifficulty(List<Note> notes, int tempo) {
    if (notes.isEmpty) return 'beginner';

    // 基于音域、速度、音符密度判断
    int minPitch = 127, maxPitch = 0;
    double totalDuration = 0;
    
    for (final note in notes) {
      if (note.pitchNumber < minPitch) minPitch = note.pitchNumber;
      if (note.pitchNumber > maxPitch) maxPitch = note.pitchNumber;
      totalDuration += note.duration;
    }

    final pitchRange = maxPitch - minPitch;
    final noteDensity = notes.length / (totalDuration > 0 ? totalDuration : 1);

    // 简单规则
    if (pitchRange > 48 || tempo > 140 || noteDensity > 4) {
      return 'advanced';
    } else if (pitchRange > 30 || tempo > 120 || noteDensity > 2.5) {
      return 'intermediate';
    }
    return 'beginner';
  }
}

/// 乐谱元数据
class _ScoreMetadata {
  final String title;
  final String composer;
  final int tempo;
  final String? category;

  _ScoreMetadata({
    required this.title,
    required this.composer,
    required this.tempo,
    this.category,
  });
}

/// 声部定义
class _PartDef {
  final String id;
  final String name;
  final String? instrument;

  _PartDef({required this.id, required this.name, this.instrument});
}

/// 解析异常
class MusicXmlParseException implements Exception {
  final String message;
  MusicXmlParseException(this.message);

  @override
  String toString() => 'MusicXmlParseException: $message';
}
