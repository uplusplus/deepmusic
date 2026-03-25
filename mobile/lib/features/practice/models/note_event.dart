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
