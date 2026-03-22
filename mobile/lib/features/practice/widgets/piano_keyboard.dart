import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../midi/services/midi_service.dart';
import '../../settings/services/app_settings.dart';
import '../services/audio_synth_service.dart';

/// 完整 88 键钢琴键盘控件
///
/// 范围: A0 (MIDI 21) → C8 (MIDI 108)
/// 特性：
/// - 横向滚动，覆盖完整 88 键
/// - 自动跟随当前音区
/// - 触摸响应 + 内置音频合成
/// - MIDI 设备联动
/// - 高亮应弹音符
class PianoKeyboard extends StatefulWidget {
  /// 应弹的音高集合（来自 ScoreFollower）
  final Set<int> expectedPitches;

  /// 高度
  final double height;

  /// 键被按下时的回调
  final void Function(int note, int velocity)? onNoteOn;

  /// 键释放时的回调
  final void Function(int note)? onNoteOff;

  const PianoKeyboard({
    super.key,
    required this.expectedPitches,
    this.height = 120,
    this.onNoteOn,
    this.onNoteOff,
  });

  @override
  State<PianoKeyboard> createState() => _PianoKeyboardState();
}

class _PianoKeyboardState extends State<PianoKeyboard> {
  final MidiService _midiService = MidiService();
  final AudioSynthService _synthService = AudioSynthService();
  final ScrollController _scrollCtrl = ScrollController();
  StreamSubscription<MidiEvent>? _midiSub;

  /// 当前按下的音符集合
  final Set<int> _pressedNotes = {};

  /// 当前触摸指针对应的音符（pointerId → noteNumber）
  final Map<int, int> _touchPointers = {};

  /// 最近按下的音符
  int? _lastPressedNote;

  // ── 88 键常量 ──
  static const int _startNote = 21;  // A0
  static const int _endNote = 108;   // C8
  static const int _totalNotes = _endNote - _startNote + 1; // 88
  // 白键音名 pattern: C D E F G A B (半音偏移 0 2 4 5 7 9 11)
  static const _whiteKeyPattern = [0, 2, 4, 5, 7, 9, 11];
  // 黑键半音值
  static const _blackSemitones = {1, 3, 6, 8, 10};
  // 黑键在白键 pattern 中的前一个白键索引
  static const _blackKeyAfterWhite = {1: 0, 3: 1, 6: 3, 8: 4, 10: 5};

  // 88 键中白键总数 (A0..C8: A B + 7 octaves × 7 = 52)
  static const _totalWhiteKeys = 52;

  @override
  void initState() {
    super.initState();
    _midiSub = _midiService.midiStream.listen(_onMidiEvent);
    _initSynth();
    // 首帧后滚到 C4 附近
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToNote(60));
  }

  Future<void> _initSynth() async {
    if (!_synthService.isInitialized) {
      await _synthService.init();
    }
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
    // MIDI 按键时自动滚到该音区
    if (event.type == MidiEventType.noteOn && event.velocity > 0) {
      _scrollToNote(event.note);
    }
  }

  /// 自动滚动使目标音符居中
  void _scrollToNote(int note) {
    if (!_scrollCtrl.hasClients) return;
    final whiteIdx = _noteToWhiteIndex(note);
    final keyWidth = _keyWidth;
    final targetOffset = whiteIdx * keyWidth - (context.size?.width ?? 300) / 2 + keyWidth;
    final maxScroll = _scrollCtrl.position.maxScrollExtent;
    _scrollCtrl.animateTo(
      targetOffset.clamp(0, maxScroll),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  /// MIDI note → 白键全局索引 (0-based)
  int _noteToWhiteIndex(int note) {
    int count = 0;
    for (int n = _startNote; n < note; n++) {
      if (!_blackSemitones.contains(n % 12)) count++;
    }
    return count;
  }

  /// 白键宽度（固定）
  double get _keyWidth => 38.0;
  double get _blackKeyWidth => _keyWidth * 0.58;

  // ── 触摸弹奏 ──

  void _handleNoteDown(int note, {int velocity = 100}) {
    if (!mounted) return;
    setState(() {
      _pressedNotes.add(note);
      _lastPressedNote = note;
    });
    final isMidiMode = AppSettings().audioOutputMode == AudioOutputMode.midi;
    if (isMidiMode) {
      _midiService.sendNoteOn(note, velocity);
    } else {
      _synthService.noteOn(note, velocity);
    }
    widget.onNoteOn?.call(note, velocity);
  }

  void _handleNoteUp(int note) {
    if (!mounted) return;
    setState(() {
      _pressedNotes.remove(note);
    });
    final isMidiMode = AppSettings().audioOutputMode == AudioOutputMode.midi;
    if (isMidiMode) {
      _midiService.sendNoteOff(note);
    } else {
      _synthService.noteOff(note);
    }
    widget.onNoteOff?.call(note);
  }

  /// 根据触摸位置命中的音符（localPosition 相对滚动内容）
  int? _hitTestKey(Offset localPosition) {
    final wkWidth = _keyWidth;
    final bkWidth = _blackKeyWidth;
    final keyHeight = widget.height - 4;

    // 先检查黑键
    for (int noteNum = _startNote; noteNum <= _endNote; noteNum++) {
      final semitone = noteNum % 12;
      if (!_blackSemitones.contains(semitone)) continue;

      final afterWhiteIdx = _blackKeyAfterWhite[semitone]!;
      final octave = noteNum ~/ 12;
      final targetWhiteNote = octave * 12 + _whiteKeyPattern[afterWhiteIdx];
      final globalWhiteIdx = _noteToWhiteIndex(targetWhiteNote);

      final left = (globalWhiteIdx + 1) * wkWidth - bkWidth / 2;
      final blackHeight = keyHeight * 0.62;

      if (localPosition.dx >= left && localPosition.dx <= left + bkWidth &&
          localPosition.dy >= 0 && localPosition.dy <= blackHeight) {
        return noteNum;
      }
    }

    // 再检查白键
    final col = (localPosition.dx / wkWidth).floor().clamp(0, _totalWhiteKeys - 1);
    int wIdx = 0;
    for (int noteNum = _startNote; noteNum <= _endNote; noteNum++) {
      if (!_blackSemitones.contains(noteNum % 12)) {
        if (wIdx == col) return noteNum;
        wIdx++;
      }
    }

    return null;
  }

  @override
  void dispose() {
    _midiSub?.cancel();
    _scrollCtrl.dispose();
    final isMidiMode = AppSettings().audioOutputMode == AudioOutputMode.midi;
    for (final note in _touchPointers.values) {
      if (isMidiMode) {
        _midiService.sendNoteOff(note);
      } else {
        _synthService.noteOff(note);
      }
    }
    _touchPointers.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final totalWidth = _totalWhiteKeys * _keyWidth;
    final keyHeight = widget.height - 4;

    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[100],
        border: Border(
          top: BorderSide(color: AppColors.divider),
          bottom: BorderSide(color: AppColors.divider),
        ),
      ),
      child: Listener(
        onPointerDown: (event) {
          // 需要加上 scroll offset 才是内容坐标
          final scrollOffset = _scrollCtrl.hasClients ? _scrollCtrl.offset : 0.0;
          final contentPos = Offset(event.localPosition.dx + scrollOffset, event.localPosition.dy);
          final note = _hitTestKey(contentPos);
          if (note != null) {
            _touchPointers[event.pointer] = note;
            _handleNoteDown(note, velocity: 100);
          }
        },
        onPointerUp: (event) {
          final note = _touchPointers.remove(event.pointer);
          if (note != null) _handleNoteUp(note);
        },
        onPointerCancel: (event) {
          final note = _touchPointers.remove(event.pointer);
          if (note != null) _handleNoteUp(note);
        },
        child: SingleChildScrollView(
          controller: _scrollCtrl,
          scrollDirection: Axis.horizontal,
          physics: const ClampingScrollPhysics(),
          child: SizedBox(
            width: totalWidth,
            height: widget.height,
            child: CustomPaint(
              painter: _PianoPainter(
                startNote: _startNote,
                totalWhiteKeys: _totalWhiteKeys,
                whiteKeyWidth: _keyWidth,
                blackKeyWidth: _blackKeyWidth,
                keyHeight: keyHeight,
                pressedNotes: _pressedNotes,
                expectedPitches: widget.expectedPitches,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// CustomPainter 高性能渲染 88 键
// ═══════════════════════════════════════════════════════════════

class _PianoPainter extends CustomPainter {
  final int startNote;
  final int totalWhiteKeys;
  final double whiteKeyWidth;
  final double blackKeyWidth;
  final double keyHeight;
  final Set<int> pressedNotes;
  final Set<int> expectedPitches;

  static const _whiteKeyPattern = [0, 2, 4, 5, 7, 9, 11];
  static const _blackSemitones = {1, 3, 6, 8, 10};
  static const _blackKeyAfterWhite = {1: 0, 3: 1, 6: 3, 8: 4, 10: 5};
  static const _whiteNames = ['C', 'D', 'E', 'F', 'G', 'A', 'B'];

  _PianoPainter({
    required this.startNote,
    required this.totalWhiteKeys,
    required this.whiteKeyWidth,
    required this.blackKeyWidth,
    required this.keyHeight,
    required this.pressedNotes,
    required this.expectedPitches,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawWhiteKeys(canvas);
    _drawBlackKeys(canvas);
  }

  void _drawWhiteKeys(Canvas canvas) {
    final whitePaint = Paint();
    final pressedPaint = Paint()..color = AppColors.accent.withOpacity(0.3);
    final expectedPaint = Paint()..color = AppColors.primaryLight;
    final borderPaint = Paint()
      ..color = Colors.grey[300]!
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    final pressedBorderPaint = Paint()
      ..color = AppColors.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    int wIdx = 0;
    for (int noteNum = startNote; noteNum <= 108 && wIdx < totalWhiteKeys; noteNum++) {
      final semitone = noteNum % 12;
      if (_blackSemitones.contains(semitone)) continue;

      final x = wIdx * whiteKeyWidth;
      final rect = Rect.fromLTWH(x + 0.5, 0, whiteKeyWidth - 1, keyHeight);
      final rRect = RRect.fromRectAndCorners(rect,
        bottomLeft: const Radius.circular(4),
        bottomRight: const Radius.circular(4),
      );

      final isPressed = pressedNotes.contains(noteNum);
      final isExpected = expectedPitches.contains(noteNum);

      if (isPressed) {
        canvas.drawRRect(rRect, pressedPaint);
        canvas.drawRRect(rRect, pressedBorderPaint);
        // 按下发光效果
        canvas.drawRRect(rRect, Paint()
          ..color = AppColors.accent.withOpacity(0.15)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
      } else if (isExpected) {
        canvas.drawRRect(rRect, expectedPaint);
        canvas.drawRRect(rRect, borderPaint);
      } else {
        whitePaint.color = Colors.white;
        canvas.drawRRect(rRect, whitePaint);
        canvas.drawRRect(rRect, borderPaint);
      }

      // 音名标签
      final octave = (noteNum ~/ 12) - 1;
      final nameIdx = _whiteKeyPattern.indexOf(semitone);
      if (nameIdx >= 0) {
        final tp = TextPainter(
          text: TextSpan(
            text: '${_whiteNames[nameIdx]}$octave',
            style: TextStyle(
              fontSize: 9,
              color: isPressed ? AppColors.accent : (isExpected ? AppColors.primary : Colors.grey[400]),
              fontWeight: isPressed || isExpected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x + (whiteKeyWidth - tp.width) / 2, keyHeight - tp.height - 4));
      }

      wIdx++;
    }
  }

  void _drawBlackKeys(Canvas canvas) {
    final blackPaint = Paint();
    final pressedPaint = Paint()..color = AppColors.accent;
    final expectedPaint = Paint()..color = AppColors.primary;
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    final pressedGlowPaint = Paint()
      ..color = AppColors.accent.withOpacity(0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

    final blackHeight = keyHeight * 0.62;

    for (int noteNum = startNote; noteNum <= 108; noteNum++) {
      final semitone = noteNum % 12;
      if (!_blackSemitones.contains(semitone)) continue;

      final afterWhiteIdx = _blackKeyAfterWhite[semitone]!;
      final octave = noteNum ~/ 12;
      final targetWhiteNote = octave * 12 + _whiteKeyPattern[afterWhiteIdx];
      final globalWhiteIdx = _noteToWhiteIndex(targetWhiteNote);

      final x = (globalWhiteIdx + 1) * whiteKeyWidth - blackKeyWidth / 2;
      final rect = Rect.fromLTWH(x, 0, blackKeyWidth, blackHeight);
      final rRect = RRect.fromRectAndCorners(rect,
        bottomLeft: const Radius.circular(3),
        bottomRight: const Radius.circular(3),
      );

      final isPressed = pressedNotes.contains(noteNum);
      final isExpected = expectedPitches.contains(noteNum);

      // 投影
      if (!isPressed) {
        canvas.drawRRect(rRect, shadowPaint);
      }

      if (isPressed) {
        canvas.drawRRect(rRect, pressedGlowPaint);
        canvas.drawRRect(rRect, pressedPaint);
      } else if (isExpected) {
        canvas.drawRRect(rRect, expectedPaint);
      } else {
        blackPaint.color = Colors.grey[850]!;
        canvas.drawRRect(rRect, blackPaint);
      }
    }
  }

  int _noteToWhiteIndex(int note) {
    int count = 0;
    for (int n = startNote; n < note; n++) {
      if (!_blackSemitones.contains(n % 12)) count++;
    }
    return count;
  }

  @override
  bool shouldRepaint(covariant _PianoPainter old) {
    return old.pressedNotes != pressedNotes || old.expectedPitches != expectedPitches;
  }
}
