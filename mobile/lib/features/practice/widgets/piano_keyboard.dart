import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../midi/services/midi_service.dart';

/// 钢琴键盘控件
///
/// 特性：
/// - 真实钢琴比例（黑键叠在白键上方）
/// - 标注音名
/// - 高亮应弹音符（primary）
/// - 实时高亮已按下的 MIDI 键（accent）
/// - 自动跟随当前音区
class PianoKeyboard extends StatefulWidget {
  /// 应弹的音高集合（来自 ScoreFollower）
  final Set<int> expectedPitches;

  /// 当前基准音区（0-based），键盘会居中显示 2 个八度
  /// 如果为 null，则自动从 expectedPitches 推算
  final int? baseOctave;

  /// 高度
  final double height;

  const PianoKeyboard({
    super.key,
    required this.expectedPitches,
    this.baseOctave,
    this.height = 120,
  });

  @override
  State<PianoKeyboard> createState() => _PianoKeyboardState();
}

class _PianoKeyboardState extends State<PianoKeyboard> {
  final MidiService _midiService = MidiService();
  StreamSubscription<MidiEvent>? _midiSub;

  /// 当前按下的音符集合
  final Set<int> _pressedNotes = {};

  /// 最近按下的音符（用于确定自动跟随的音区）
  int? _lastPressedNote;

  @override
  void initState() {
    super.initState();
    _midiSub = _midiService.midiStream.listen(_onMidiEvent);
  }

  void _onMidiEvent(MidiEvent event) {
    if (!mounted) return;
    setState(() {
      if (event.type == MidiEventType.noteOn && event.velocity > 0) {
        _pressedNotes.add(event.note);
        _lastPressedNote = event.note;
      } else if (event.type == MidiEventType.noteOff ||
          (event.type == MidiEventType.noteOn && event.velocity == 0)) {
        _pressedNotes.remove(event.note);
      }
    });
  }

  @override
  void dispose() {
    _midiSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 计算基准音区
    int baseOctave;
    if (widget.baseOctave != null) {
      baseOctave = widget.baseOctave!;
    } else if (_lastPressedNote != null) {
      baseOctave = (_lastPressedNote! ~/ 12) - 1;
    } else if (widget.expectedPitches.isNotEmpty) {
      baseOctave = (widget.expectedPitches.first ~/ 12) - 1;
    } else {
      baseOctave = 4; // 默认 C4
    }

    final baseNote = (baseOctave + 1) * 12; // baseOctave=4 → C4 (note 60)
    final noteRange = 24; // 2 octaves

    return Container(
      height: widget.height,
      color: Colors.grey[100],
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Center(
        child: _buildPianoRow(baseNote, noteRange),
      ),
    );
  }

  Widget _buildPianoRow(int startNote, int count) {
    // 白键音名
    const whiteNames = ['C', 'D', 'E', 'F', 'G', 'A', 'B'];
    const whiteKeyPattern = [0, 2, 4, 5, 7, 9, 11]; // C D E F G A B 的半音偏移
    // 黑键在白键序列中的位置比例 (0-1)
    // C#=在C与D之间, D#=在D与E之间, 无E#, F#=在F与G之间, G#=在G与A之间, A#=在A与B之间
    const blackKeyOffsets = {
      1: 0.63,  // C# 在 C 之后
      3: 0.63,  // D# 在 D 之后
      6: 0.63,  // F# 在 F 之后
      8: 0.63,  // G# 在 G 之后
      10: 0.63, // A# 在 A 之后
    };

    // 收集白键和黑键
    final whiteKeys = <_PianoKey>[];
    final blackKeys = <_PianoKey>[];

    for (int i = 0; i < count; i++) {
      final noteNum = startNote + i;
      final semitone = noteNum % 12;
      final octave = (noteNum ~/ 12) - 1;
      final isBlack = [1, 3, 6, 8, 10].contains(semitone);

      if (isBlack) {
        blackKeys.add(_PianoKey(
          noteNumber: noteNum,
          isBlack: true,
          label: null,
          isExpected: widget.expectedPitches.contains(noteNum),
          isPressed: _pressedNotes.contains(noteNum),
        ));
      } else {
        final whiteIndex = whiteKeyPattern.indexOf(semitone);
        final name = whiteIndex >= 0 ? whiteNames[whiteIndex] : '?';
        whiteKeys.add(_PianoKey(
          noteNumber: noteNum,
          isBlack: false,
          label: '$name$octave',
          isExpected: widget.expectedPitches.contains(noteNum),
          isPressed: _pressedNotes.contains(noteNum),
        ));
      }
    }

    final whiteKeyWidth = 1.0 / whiteKeys.length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final availableHeight = constraints.maxHeight;

        // 真实钢琴比例：白键宽高比约 1:5.5 (23mm × 150mm)，取 1:6 更美观
        const maxWhiteKeyWidth = 44.0;
        final idealWidth = whiteKeys.length * maxWhiteKeyWidth;
        // 不超过可用宽度，不超过理想宽度
        final totalWidth = idealWidth.clamp(0.0, availableWidth);
        final actualWhiteKeyWidth = totalWidth / whiteKeys.length;
        final blackKeyWidth = actualWhiteKeyWidth * 0.58;

        return Center(
          child: SizedBox(
            width: totalWidth,
            child: Stack(
              children: [
                // 白键层
                Row(
                  children: whiteKeys.map((key) {
                    return SizedBox(
                      width: actualWhiteKeyWidth,
                      height: availableHeight - 4,
                      child: _WhiteKey(
                        label: key.label!,
                        isExpected: key.isExpected,
                        isPressed: key.isPressed,
                      ),
                    );
                  }).toList(),
                ),

                // 黑键层
                ..._buildBlackKeys(blackKeys, whiteKeys, actualWhiteKeyWidth, blackKeyWidth),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildBlackKeys(
    List<_PianoKey> blackKeys,
    List<_PianoKey> whiteKeys,
    double whiteKeyWidth,
    double blackKeyWidth,
  ) {
    const whiteKeyPattern = [0, 2, 4, 5, 7, 9, 11];
    const blackKeyAfterWhite = {
      1: 0,   // C# after C (white index 0)
      3: 1,   // D# after D (white index 1)
      6: 3,   // F# after F (white index 3)
      8: 4,   // G# after G (white index 4)
      10: 5,  // A# after A (white index 5)
    };

    final widgets = <Widget>[];

    for (final bk in blackKeys) {
      final semitone = bk.noteNumber % 12;
      final afterWhiteIdx = blackKeyAfterWhite[semitone];
      if (afterWhiteIdx == null) continue;

      // 找到对应的白键在整个白键列表中的位置
      final octave = bk.noteNumber ~/ 12;
      final baseNote = octave * 12;
      final targetWhiteNote = baseNote + whiteKeyPattern[afterWhiteIdx];

      int globalWhiteIdx = 0;
      for (int i = 0; i < whiteKeys.length; i++) {
        if (whiteKeys[i].noteNumber == targetWhiteNote) {
          globalWhiteIdx = i;
          break;
        }
      }

      final left = (globalWhiteIdx + 1) * whiteKeyWidth - blackKeyWidth / 2;

      widgets.add(Positioned(
        left: left,
        top: 0,
        width: blackKeyWidth,
        height: (widget.height - 4) * 0.62,
        child: _BlackKey(
          isExpected: bk.isExpected,
          isPressed: bk.isPressed,
        ),
      ));
    }

    return widgets;
  }
}

class _PianoKey {
  final int noteNumber;
  final bool isBlack;
  final String? label;
  final bool isExpected;
  final bool isPressed;

  _PianoKey({
    required this.noteNumber,
    required this.isBlack,
    this.label,
    required this.isExpected,
    required this.isPressed,
  });
}

/// 白键
class _WhiteKey extends StatelessWidget {
  final String label;
  final bool isExpected;
  final bool isPressed;

  const _WhiteKey({
    required this.label,
    required this.isExpected,
    required this.isPressed,
  });

  @override
  Widget build(BuildContext context) {
    Color bgColor;
    Color borderColor;
    Color textColor;

    if (isPressed) {
      bgColor = AppColors.accent.withOpacity(0.3);
      borderColor = AppColors.accent;
      textColor = AppColors.accent;
    } else if (isExpected) {
      bgColor = AppColors.primaryLight;
      borderColor = AppColors.primary.withOpacity(0.5);
      textColor = AppColors.primary;
    } else {
      bgColor = Colors.white;
      borderColor = Colors.grey[300]!;
      textColor = Colors.grey[500]!;
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 80),
      margin: const EdgeInsets.symmetric(horizontal: 0.5),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border.all(color: borderColor, width: isPressed ? 1.5 : 0.8),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(4),
          bottomRight: Radius.circular(4),
        ),
        boxShadow: isPressed
            ? [BoxShadow(color: AppColors.accent.withOpacity(0.3), blurRadius: 6)]
            : null,
      ),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: isExpected || isPressed ? FontWeight.w600 : FontWeight.normal,
              color: textColor,
            ),
          ),
        ),
      ),
    );
  }
}

/// 黑键
class _BlackKey extends StatelessWidget {
  final bool isExpected;
  final bool isPressed;

  const _BlackKey({
    required this.isExpected,
    required this.isPressed,
  });

  @override
  Widget build(BuildContext context) {
    Color bgColor;

    if (isPressed) {
      bgColor = AppColors.accent;
    } else if (isExpected) {
      bgColor = AppColors.primary;
    } else {
      bgColor = Colors.grey[850]!;
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 80),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(3),
          bottomRight: Radius.circular(3),
        ),
        boxShadow: isPressed
            ? [BoxShadow(color: AppColors.accent.withOpacity(0.4), blurRadius: 8)]
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                ),
              ],
      ),
    );
  }
}
