import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';

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
  final int note;
  final int velocity;
  final int channel;
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
  scanning,
  connecting,
  connected,
  error,
}

/// MIDI 服务
/// 
/// 使用 flutter_midi_command 管理蓝牙 MIDI 连接和事件处理
class MidiService {
  static final MidiService _instance = MidiService._internal();
  factory MidiService() => _instance;
  MidiService._internal();

  final _midiCommand = MidiCommand();
  
  final _connectionStateController = StreamController<MidiConnectionState>.broadcast();
  final _midiEventController = StreamController<MidiEvent>.broadcast();
  final _devicesController = StreamController<List<MidiDevice>>.broadcast();

  MidiDevice? _connectedDevice;
  MidiConnectionState _connectionState = MidiConnectionState.disconnected;
  StreamSubscription? _midiDataStreamSubscription;
  StreamSubscription? _deviceDiscoverySubscription;

  final List<MidiDevice> _discoveredDevices = [];

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

  /// 检查蓝牙是否可用
  Future<bool> isBluetoothAvailable() async {
    try {
      final state = await _midiCommand.bluetoothState;
      return state == BluetoothState.poweredOn;
    } catch (e) {
      debugPrint('[MidiService] Bluetooth check failed: $e');
      return false;
    }
  }

  /// 扫描 MIDI 设备
  Future<List<MidiDevice>> scanDevices() async {
    debugPrint('[MidiService] Scanning for devices...');
    _updateState(MidiConnectionState.scanning);
    _discoveredDevices.clear();

    try {
      // 开始蓝牙扫描
      await _midiCommand.startScanningForBluetoothDevices();

      // 监听发现的设备
      _deviceDiscoverySubscription?.cancel();
      _deviceDiscoverySubscription = _midiCommand.onMidiSetupChanged?.listen((event) {
        debugPrint('[MidiService] Device setup changed: $event');
        _refreshDeviceList();
      });

      // 等待扫描结果 (3秒)
      await Future.delayed(const Duration(seconds: 3));
      
      // 停止扫描
      await _midiCommand.stopScanningForBluetoothDevices();

      // 获取已知设备
      await _refreshDeviceList();

      _updateState(
        _connectedDevice != null 
          ? MidiConnectionState.connected 
          : MidiConnectionState.disconnected
      );

      return _discoveredDevices;
    } catch (e) {
      debugPrint('[MidiService] Scan failed: $e');
      _updateState(MidiConnectionState.error);
      return _discoveredDevices;
    }
  }

  /// 刷新设备列表
  Future<void> _refreshDeviceList() async {
    try {
      final devices = await _midiCommand.devices;
      if (devices != null) {
        _discoveredDevices.clear();
        for (final device in devices) {
          _discoveredDevices.add(MidiDevice(
            id: device.id,
            name: device.name ?? 'Unknown MIDI Device',
            manufacturer: _extractManufacturer(device.name),
            isConnected: device.connected ?? false,
          ));
        }
        _devicesController.add(List.unmodifiable(_discoveredDevices));
      }
    } catch (e) {
      debugPrint('[MidiService] Refresh devices failed: $e');
    }
  }

  /// 从设备名称提取制造商
  String? _extractManufacturer(String? name) {
    if (name == null) return null;
    final manufacturers = ['Yamaha', 'Roland', 'Kawai', 'Casio', 'Korg', 'Nord', 'Kurzweil'];
    for (final m in manufacturers) {
      if (name.toLowerCase().contains(m.toLowerCase())) return m;
    }
    return null;
  }

  /// 连接设备
  Future<bool> connect(MidiDevice device) async {
    debugPrint('[MidiService] Connecting to ${device.name}...');
    _updateState(MidiConnectionState.connecting);

    try {
      // 查找底层设备对象
      final midiDevices = await _midiCommand.devices;
      if (midiDevices == null) {
        throw Exception('无法获取设备列表');
      }

      dynamic targetDevice;
      for (final d in midiDevices) {
        if (d.id == device.id) {
          targetDevice = d;
          break;
        }
      }

      if (targetDevice == null) {
        throw Exception('设备未找到: ${device.name}');
      }

      // 建立连接
      await _midiCommand.connectToDevice(targetDevice);

      _connectedDevice = device.copyWith(isConnected: true);
      _updateState(MidiConnectionState.connected);

      // 开始监听 MIDI 数据
      _startMidiListening();

      debugPrint('[MidiService] Connected to ${device.name}');
      return true;
    } catch (e) {
      debugPrint('[MidiService] Connection failed: $e');
      _updateState(MidiConnectionState.error);
      return false;
    }
  }

  /// 开始监听 MIDI 事件
  void _startMidiListening() {
    _midiDataStreamSubscription?.cancel();
    
    _midiDataStreamSubscription = _midiCommand.onMidiDataReceived?.listen((packet) {
      _handleMidiPacket(packet.data, packet.device);
    });

    debugPrint('[MidiService] Started listening for MIDI events');
  }

  /// 处理 MIDI 数据包
  void _handleMidiPacket(List<int> data, dynamic device) {
    if (data.isEmpty) return;

    final statusByte = data[0];
    final channel = statusByte & 0x0F;
    final messageType = statusByte & 0xF0;

    MidiEventType? eventType;
    int note = 0;
    int velocity = 0;

    switch (messageType) {
      case 0x90: // Note On
        if (data.length >= 3) {
          note = data[1];
          velocity = data[2];
          eventType = velocity > 0 
            ? MidiEventType.noteOn 
            : MidiEventType.noteOff; // velocity=0 视为 note off
        }
        break;
      case 0x80: // Note Off
        if (data.length >= 3) {
          note = data[1];
          velocity = data[2];
          eventType = MidiEventType.noteOff;
        }
        break;
      case 0xB0: // Control Change
        if (data.length >= 3) {
          eventType = MidiEventType.controlChange;
          note = data[1]; // controller number
          velocity = data[2]; // value
        }
        break;
      case 0xE0: // Pitch Bend
        if (data.length >= 3) {
          eventType = MidiEventType.pitchBend;
          note = data[1] | (data[2] << 7); // 14-bit value
          velocity = 0;
        }
        break;
    }

    if (eventType != null) {
      final event = MidiEvent(
        type: eventType,
        note: note,
        velocity: velocity,
        channel: channel,
      );
      _midiEventController.add(event);
    }
  }

  /// 发送 MIDI 事件
  Future<void> sendNoteOn(int note, int velocity, {int channel = 0}) async {
    final data = [0x90 | channel, note.clamp(0, 127), velocity.clamp(0, 127)];
    await _midiCommand.sendData(Uint8List.fromList(data));
  }

  Future<void> sendNoteOff(int note, {int channel = 0}) async {
    final data = [0x80 | channel, note.clamp(0, 127), 0];
    await _midiCommand.sendData(Uint8List.fromList(data));
  }

  /// 断开连接
  Future<void> disconnect() async {
    debugPrint('[MidiService] Disconnecting...');

    _midiDataStreamSubscription?.cancel();
    _midiDataStreamSubscription = null;

    if (_connectedDevice != null) {
      try {
        final midiDevices = await _midiCommand.devices;
        if (midiDevices != null) {
          for (final d in midiDevices) {
            if (d.id == _connectedDevice!.id) {
              await _midiCommand.disconnectDevice(d);
              break;
            }
          }
        }
      } catch (e) {
        debugPrint('[MidiService] Disconnect error: $e');
      }
    }

    _connectedDevice = null;
    _updateState(MidiConnectionState.disconnected);
    debugPrint('[MidiService] Disconnected');
  }

  /// 更新连接状态
  void _updateState(MidiConnectionState state) {
    _connectionState = state;
    _connectionStateController.add(state);
  }

  /// 发送测试事件 (调试用)
  void sendTestEvent(MidiEvent event) {
    _midiEventController.add(event);
  }

  /// 释放资源
  void dispose() {
    _midiDataStreamSubscription?.cancel();
    _deviceDiscoverySubscription?.cancel();
    _connectionStateController.close();
    _midiEventController.close();
    _devicesController.close();
  }
}
