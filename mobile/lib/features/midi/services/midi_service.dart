import 'dart:async';
import 'package:flutter/foundation.dart';

/// MIDI 事件类型
enum MidiEventType {
  noteOn,
  noteOff,
  controlChange,
  pitchBend,
}

/// MIDI 事件
class MidiEvent {
  final MidiEventType type;
  final int note;       // 0-127 (C0-C10)
  final int velocity;   // 0-127
  final int channel;    // 0-15
  final DateTime timestamp;

  MidiEvent({
    required this.type,
    required this.note,
    required this.velocity,
    required this.channel,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// 获取音符名称 (C4, D#5, etc.)
  String get noteName {
    const noteNames = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
    final octave = (note ~/ 12) - 1;
    final noteIndex = note % 12;
    return '${noteNames[noteIndex]}$octave';
  }

  @override
  String toString() => 'MidiEvent(${type.name}, $noteName, vel=$velocity)';
}

/// MIDI 设备
class MidiDevice {
  final String id;
  final String name;
  final String? manufacturer;
  final bool isConnected;

  MidiDevice({
    required this.id,
    required this.name,
    this.manufacturer,
    this.isConnected = false,
  });

  MidiDevice copyWith({
    String? id,
    String? name,
    String? manufacturer,
    bool? isConnected,
  }) {
    return MidiDevice(
      id: id ?? this.id,
      name: name ?? this.name,
      manufacturer: manufacturer ?? this.manufacturer,
      isConnected: isConnected ?? this.isConnected,
    );
  }
}

/// MIDI 连接状态
enum MidiConnectionState {
  disconnected,
  connecting,
  connected,
  error,
}

/// MIDI 服务
/// 
/// 负责管理蓝牙 MIDI 连接和事件处理
class MidiService {
  static final MidiService _instance = MidiService._internal();
  factory MidiService() => _instance;
  MidiService._internal();

  final _connectionStateController = StreamController<MidiConnectionState>.broadcast();
  final _midiEventController = StreamController<MidiEvent>.broadcast();
  final _devicesController = StreamController<List<MidiDevice>>.broadcast();

  MidiDevice? _connectedDevice;
  MidiConnectionState _connectionState = MidiConnectionState.disconnected;

  /// 连接状态流
  Stream<MidiConnectionState> get connectionState => _connectionStateController.stream;

  /// MIDI 事件流
  Stream<MidiEvent> get midiStream => _midiEventController.stream;

  /// 设备列表流
  Stream<List<MidiDevice>> get devices => _devicesController.stream;

  /// 当前连接的设备
  MidiDevice? get connectedDevice => _connectedDevice;

  /// 当前连接状态
  MidiConnectionState get currentState => _connectionState;

  /// 扫描 MIDI 设备
  Future<List<MidiDevice>> scanDevices() async {
    debugPrint('[MidiService] Scanning for devices...');

    // TODO: 实现实际的蓝牙扫描
    // 使用 flutter_midi_command 包
    
    // 模拟返回设备列表
    final devices = [
      MidiDevice(
        id: 'yamaha-p125-001',
        name: 'Yamaha P125',
        manufacturer: 'Yamaha',
      ),
    ];

    _devicesController.add(devices);
    return devices;
  }

  /// 连接设备
  Future<bool> connect(MidiDevice device) async {
    debugPrint('[MidiService] Connecting to ${device.name}...');
    
    _connectionState = MidiConnectionState.connecting;
    _connectionStateController.add(_connectionState);

    try {
      // TODO: 实现实际的蓝牙连接
      // 使用 flutter_midi_command 包

      await Future.delayed(const Duration(seconds: 2)); // 模拟连接延迟

      _connectedDevice = device.copyWith(isConnected: true);
      _connectionState = MidiConnectionState.connected;
      _connectionStateController.add(_connectionState);

      // 开始监听 MIDI 事件
      _startMidiListening();

      debugPrint('[MidiService] Connected to ${device.name}');
      return true;
    } catch (e) {
      debugPrint('[MidiService] Connection failed: $e');
      _connectionState = MidiConnectionState.error;
      _connectionStateController.add(_connectionState);
      return false;
    }
  }

  /// 断开连接
  Future<void> disconnect() async {
    debugPrint('[MidiService] Disconnecting...');

    // TODO: 实现实际的断开连接
    // 使用 flutter_midi_command 包

    _connectedDevice = null;
    _connectionState = MidiConnectionState.disconnected;
    _connectionStateController.add(_connectionState);

    debugPrint('[MidiService] Disconnected');
  }

  /// 开始监听 MIDI 事件
  void _startMidiListening() {
    // TODO: 实现实际的 MIDI 事件监听
    // 使用 flutter_midi_command 包

    debugPrint('[MidiService] Started listening for MIDI events');
  }

  /// 发送 MIDI 事件 (用于测试)
  void sendTestEvent(MidiEvent event) {
    _midiEventController.add(event);
  }

  /// 释放资源
  void dispose() {
    _connectionStateController.close();
    _midiEventController.close();
    _devicesController.close();
  }
}
