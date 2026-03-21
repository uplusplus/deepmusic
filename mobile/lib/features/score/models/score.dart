/// 演奏手部模式
enum HandMode { both, rightOnly, leftOnly }

/// 乐谱
class Score {
  final String id;
  final String title;
  final String composer;
  final String? arranger;
  final String difficulty;  // beginner, intermediate, advanced
  final List<Part> parts;
  final int totalMeasures;
  final Duration estimatedDuration;
  final String? coverImage;
  final String musicXmlPath;
  final String? description;
  final List<String> tags;
  final DateTime addedAt;

  Score({
    required this.id,
    required this.title,
    required this.composer,
    this.arranger,
    required this.difficulty,
    required this.parts,
    required this.totalMeasures,
    required this.estimatedDuration,
    this.coverImage,
    required this.musicXmlPath,
    this.description,
    this.tags = const [],
    DateTime? addedAt,
  }) : addedAt = addedAt ?? DateTime.now();

  /// 获取所有音符 (所有声部合并，按时间排序)
  List<Note> get allNotes => _filterNotes(null);

  /// 右手音符 (staff == 1)
  List<Note> get rightHandNotes => _filterNotes(1);

  /// 左手音符 (staff == 2)
  List<Note> get leftHandNotes => _filterNotes(2);

  /// 是否有左右手区分
  bool get hasHandSeparation {
    for (final part in parts) {
      for (final measure in part.measures) {
        for (final note in measure.notes) {
          if (note.staff == 2) return true;
        }
      }
    }
    return false;
  }

  List<Note> _filterNotes(int? staff) {
    final notes = <Note>[];
    for (final part in parts) {
      for (final measure in part.measures) {
        if (staff == null) {
          notes.addAll(measure.notes);
        } else {
          notes.addAll(measure.notes.where((n) => n.staff == staff || n.staff == 0));
        }
      }
    }
    notes.sort((a, b) => a.startMs.compareTo(b.startMs));
    return notes;
  }

  /// 格式化时长
  String get formattedDuration {
    final minutes = estimatedDuration.inMinutes;
    final seconds = estimatedDuration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  /// 难度显示名称
  String get difficultyDisplayName {
    switch (difficulty) {
      case 'beginner':
        return '初级';
      case 'intermediate':
        return '中级';
      case 'advanced':
        return '高级';
      default:
        return difficulty;
    }
  }
}

/// 声部
class Part {
  final String name;
  final List<Measure> measures;

  Part({
    required this.name,
    required this.measures,
  });
}

/// 小节
class Measure {
  final int number;
  final List<Note> notes;
  final TimeSignature timeSignature;
  final KeySignature keySignature;

  Measure({
    required this.number,
    required this.notes,
    required this.timeSignature,
    required this.keySignature,
  });
}

/// 拍号
class TimeSignature {
  final int beats;
  final int beatType;

  TimeSignature({
    required this.beats,
    required this.beatType,
  });

  @override
  String toString() => '$beats/$beatType';

  /// 常见拍号
  static TimeSignature get common => TimeSignature(beats: 4, beatType: 4);
  static TimeSignature get waltz => TimeSignature(beats: 3, beatType: 4);
}

/// 调号
class KeySignature {
  final int fifths;  // 正数表示升号，负数表示降号
  final String mode; // major 或 minor

  KeySignature({
    required this.fifths,
    required this.mode,
  });

  /// 获取调号名称
  String get name {
    const majorKeys = ['C', 'G', 'D', 'A', 'E', 'B', 'F#', 'C#'];
    const minorKeys = ['A', 'E', 'B', 'F#', 'C#', 'G#', 'D#', 'A#'];
    const flatMajorKeys = ['C', 'F', 'Bb', 'Eb', 'Ab', 'Db', 'Gb', 'Cb'];
    const flatMinorKeys = ['A', 'D', 'G', 'C', 'F', 'Bb', 'Eb', 'Ab'];

    if (fifths >= 0) {
      return mode == 'major'
        ? '${majorKeys[fifths]} Major'
        : '${minorKeys[fifths]} Minor';
    } else {
      return mode == 'major'
        ? '${flatMajorKeys[-fifths]} Major'
        : '${flatMinorKeys[-fifths]} Minor';
    }
  }

  /// 常见调号
  static KeySignature get cMajor => KeySignature(fifths: 0, mode: 'major');
  static KeySignature get gMajor => KeySignature(fifths: 1, mode: 'major');
  static KeySignature get dMajor => KeySignature(fifths: 2, mode: 'major');
  static KeySignature get aMinor => KeySignature(fifths: 0, mode: 'minor');
}

// Note 类在这里定义
class Note {
  final String pitch;
  final int pitchNumber;
  final double duration;
  final int startMs;
  final int measureNumber;
  final int staff;           // 1=高音谱/右手, 2=低音谱/左手, 0=未知
  final int staffPosition;   // 五线谱位置（已废弃，保留兼容）

  Note({
    required this.pitch,
    required this.pitchNumber,
    required this.duration,
    required this.startMs,
    required this.measureNumber,
    this.staff = 0,
    this.staffPosition = 0,
  });

  /// 是否为右手音符
  bool get isRightHand => staff == 1 || staff == 0;

  /// 是否为左手音符
  bool get isLeftHand => staff == 2;

  factory Note.fromPitchName(String pitchName, {required int measureNumber}) {
    const noteNames = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
    
    String note = pitchName.replaceAll(RegExp(r'\d'), '');
    int octave = int.parse(pitchName.replaceAll(RegExp(r'[^0-9]'), ''));
    
    int noteIndex = noteNames.indexOf(note);
    if (noteIndex == -1) {
      const flatsToSharps = {
        'Db': 'C#', 'Eb': 'D#', 'Fb': 'E', 'Gb': 'F#', 'Ab': 'G#', 'Bb': 'A#', 'Cb': 'B',
      };
      noteIndex = noteNames.indexOf(flatsToSharps[note] ?? note);
    }
    
    final pitchNumber = (octave + 1) * 12 + noteIndex;
    
    return Note(
      pitch: pitchName,
      pitchNumber: pitchNumber,
      duration: 1.0,
      startMs: 0,
      measureNumber: measureNumber,
    );
  }

  Note copyWith({
    String? pitch,
    int? pitchNumber,
    double? duration,
    int? startMs,
    int? measureNumber,
    int? staff,
  }) {
    return Note(
      pitch: pitch ?? this.pitch,
      pitchNumber: pitchNumber ?? this.pitchNumber,
      duration: duration ?? this.duration,
      startMs: startMs ?? this.startMs,
      measureNumber: measureNumber ?? this.measureNumber,
      staff: staff ?? this.staff,
    );
  }

  @override
  String toString() => 'Note($pitch, staff=$staff, measure=$measureNumber)';
}
