/// 音符
class Note {
  /// 音高名称 (C4, D#5, etc.)
  final String pitch;
  
  /// MIDI 音符号 (0-127)
  final int pitchNumber;
  
  /// 时值 (四分音符 = 1, 八分音符 = 0.5, etc.)
  final double duration;
  
  /// 开始时间 (从曲首开始的毫秒数)
  final int startMs;
  
  /// 所属小节
  final int measureNumber;
  
  /// 在小节中的位置
  final int staffPosition;

  Note({
    required this.pitch,
    required this.pitchNumber,
    required this.duration,
    required this.startMs,
    required this.measureNumber,
    this.staffPosition = 0,
  });

  /// 从音高名称解析
  factory Note.fromPitchName(String pitchName, {required int measureNumber}) {
    const noteNames = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
    
    // 解析音高名称 (例如 "C4", "D#5")
    String note = pitchName.replaceAll(RegExp(r'\d'), '');
    int octave = int.parse(pitchName.replaceAll(RegExp(r'[^0-9]'), ''));
    
    int noteIndex = noteNames.indexOf(note);
    if (noteIndex == -1) {
      // 处理降号表示 (Db = C#, etc.)
      noteIndex = noteNames.indexOf(_convertFlatToSharp(note));
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

  static String _convertFlatToSharp(String flat) {
    const flatsToSharps = {
      'Db': 'C#', 'Eb': 'D#', 'Fb': 'E', 'Gb': 'F#', 'Ab': 'G#', 'Bb': 'A#', 'Cb': 'B',
    };
    return flatsToSharps[flat] ?? flat;
  }

  @override
  String toString() => 'Note($pitch, measure=$measureNumber)';
}

/// 音符事件 (MIDI 输入)
class NoteEvent {
  final int noteNumber;
  final int velocity;
  final DateTime timestamp;
  final bool isNoteOn;

  NoteEvent({
    required this.noteNumber,
    required this.velocity,
    required this.timestamp,
    required this.isNoteOn,
  });

  /// 获取音符名称
  String get noteName {
    const noteNames = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
    final octave = (noteNumber ~/ 12) - 1;
    final noteIndex = noteNumber % 12;
    return '${noteNames[noteIndex]}$octave';
  }
}
