import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';

/// MIDI 连接类型
enum MidiConnectionType { bluetooth, usb }

/// MIDI 事件类型
enum MidiEventType { noteOn, noteOff, controlChange, pitchBend }

/// MIDI 事件
class MidiEvent {
  final MidiEventType type;
  final int note;
  final int velocity;
  final int channel;
  final DateTime timestamp;
  final MidiConnectionType source;

  MidiEvent({
    required this.type,
    required this.note,
    required this.velocity,
    required this.channel,
    DateTime? timestamp,
    this.source = MidiConnectionType.bluetooth,
  }) : timestamp = timestamp ?? DateTime.now();

  String get noteName {
    const noteNames = [
      'C', 'C#', 'D', 'D#', 'E', 'F',
      'F#', 'G', 'G#', 'A', 'A#', 'B'
    ];
    final octave = (note ~/ 12) - 1;
    final noteIndex = note % 12;
    return '${noteNames[noteIndex]}$octave';
  }

  @override
  String toString() =>
      'MidiEvent(${type.name}, $noteName, vel=$velocity, src=${source.name})';
}

/// MIDI 设备
class MidiDevice {
  final String id;
  final String name;
  final String? manufacturer;
  final bool isConnected;
  final MidiConnectionType connectionType;

  MidiDevice({
    required this.id,
    required this.name,
    this.manufacturer,
    this.isConnected = false,
    this.connectionType = MidiConnectionType.bluetooth,
  });

  MidiDevice copyWith({
    String? id,
    String? name,
    String? manufacturer,
    bool? isConnected,
    MidiConnectionType? connectionType,
  }) {
    return MidiDevice(
      id: id ?? this.id,
      name: name ?? this.name,
      manufacturer: manufacturer ?? this.manufacturer,
      isConnected: isConnected ?? this.isConnected,
      connectionType: connectionType ?? this.connectionType,
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

/// MIDI 服务 — 统一 BLE + USB 双连接
///
/// USB 连接优先（延迟更低），两种来源共享统一 Stream<MidiEvent>
class MidiService {
  static final MidiService _instance = MidiService._internal();
  factory MidiService() => _instance;
  MidiService._internal();

  final _midiCommand = MidiCommand();

  final _connectionStateController =
      StreamController<MidiConnectionState>.broadcast();
  final _midiEventController = StreamController<MidiEvent>.broadcast();
  final _devicesController = StreamController<List<MidiDevice>>.broadcast();

  MidiDevice? _connectedDevice;
  MidiConnectionType? _connectionType;
  MidiConnectionState _connectionState = MidiConnectionState.disconnected;

  StreamSubscription? _midiDataStreamSub;
  StreamSubscription? _deviceDiscoverySub;

  final List<MidiDevice> _discoveredBleDevices = [];
  final List<MidiDevice> _discoveredUsbDevices = [];

  // ──────── 公开 API ────────

  Stream<MidiConnectionState> get connectionState =>
      _connectionStateController.stream;

  Stream<MidiEvent> get midiStream => _midiEventController.stream;

  Stream<List<MidiDevice>> get devices => _devicesController.stream;

  MidiDevice? get connectedDevice => _connectedDevice;

  MidiConnectionState get currentState => _connectionState;

  MidiConnectionType? get connectionType => _connectionType;

  // ──────── 蓝牙 ────────

  Future<bool> isBluetoothAvailable() async {
    try {
      final state = await _midiCommand.bluetoothState;
      return state == BluetoothState.poweredOn;
    } catch (e) {
      debugPrint('[MidiService] Bluetooth check failed: $e');
      return false;
    }
  }

  /// 扫描所有可用设备 (BLE + USB)
  Future<List<MidiDevice>> scanAllDevices() async {
    debugPrint('[MidiService] Scanning all devices...');
    _updateState(MidiConnectionState.scanning);

    // 并行扫描
    await Future.wait([
      _scanBleDevices(),
      _scanUsbDevices(),
    ]);

    final allDevices = [
      ..._discoveredUsbDevices, // USB 优先
      ..._discoveredBleDevices,
    ];
    _devicesController.add(List.unmodifiable(allDevices));

    _updateState(
      _connectedDevice != null
          ? MidiConnectionState.connected
          : MidiConnectionState.disconnected,
    );

    return allDevices;
  }

  Future<List<MidiDevice>> _scanBleDevices() async {
    _discoveredBleDevices.clear();
    try {
      await _midiCommand.startScanningForBluetoothDevices();

      _deviceDiscoverySub?.cancel();
      _deviceDiscoverySub =
          _midiCommand.onMidiSetupChanged?.listen((event) {
        debugPrint('[MidiService] BLE setup changed: $event');
        _refreshBleDeviceList();
      });

      await Future.delayed(const Duration(seconds: 3));
      await _midiCommand.stopScanningForBluetoothDevices();
      await _refreshBleDeviceList();
    } catch (e) {
      debugPrint('[MidiService] BLE scan failed: $e');
    }
    return _discoveredBleDevices;
  }

  Future<void> _refreshBleDeviceList() async {
    try {
      final devices = await _midiCommand.devices;
      if (devices != null) {
        _discoveredBleDevices.clear();
        for (final device in devices) {
          _discoveredBleDevices.add(MidiDevice(
            id: 'ble_${device.id}',
            name: device.name ?? 'Unknown BLE MIDI',
            manufacturer: _extractManufacturer(device.name),
            isConnected: device.connected ?? false,
            connectionType: MidiConnectionType.bluetooth,
          ));
        }
      }
    } catch (e) {
      debugPrint('[MidiService] BLE refresh failed: $e');
    }
  }

  Future<List<MidiDevice>> _scanUsbDevices() async {
    _discoveredUsbDevices.clear();
    try {
      // flutter_midi_command 也管理 USB 设备
      final devices = await _midiCommand.devices;
      if (devices != null) {
        for (final device in devices) {
          // USB 设备通常没有蓝牙特征
          final name = device.name ?? 'Unknown USB MIDI';
          if (_isUsbDevice(name, device)) {
            _discoveredUsbDevices.add(MidiDevice(
              id: 'usb_${device.id}',
              name: name,
              manufacturer: _extractManufacturer(name),
              isConnected: device.connected ?? false,
              connectionType: MidiConnectionType.usb,
            ));
          }
        }
      }
      debugPrint('[MidiService] Found ${_discoveredUsbDevices.length} USB devices');
    } catch (e) {
      debugPrint('[MidiService] USB scan failed: $e');
    }
    return _discoveredUsbDevices;
  }

  bool _isUsbDevice(String name, dynamic device) {
    // 启发式判断：USB 设备名称通常不含蓝牙相关关键词
    final lowerName = name.toLowerCase();
    // MIDI over USB 的典型名称包含 "USB" 或制造商名
    return lowerName.contains('usb') ||
        lowerName.contains('midi') ||
        lowerName.contains('piano') ||
        lowerName.contains('keyboard');
  }

  // ──────── 连接 ────────

  Future<bool> connect(MidiDevice device) async {
    debugPrint('[MidiService] Connecting to ${device.name} (${device.connectionType.name})...');
    _updateState(MidiConnectionState.connecting);

    try {
      final midiDevices = await _midiCommand.devices;
      if (midiDevices == null) throw Exception('无法获取设备列表');

      // 匹配底层设备
      dynamic targetDevice;
      final rawId = device.id
          .replaceAll('ble_', '')
          .replaceAll('usb_', '');

      for (final d in midiDevices) {
        if (d.id == rawId) {
          targetDevice = d;
          break;
        }
      }

      if (targetDevice == null) {
        throw Exception('设备未找到: ${device.name}');
      }

      await _midiCommand.connectToDevice(targetDevice);

      _connectedDevice = device.copyWith(isConnected: true);
      _connectionType = device.connectionType;
      _updateState(MidiConnectionState.connected);

      _startMidiListening();

      debugPrint('[MidiService] Connected to ${device.name} via ${device.connectionType.name}');
      return true;
    } catch (e) {
      debugPrint('[MidiService] Connection failed: $e');
      _updateState(MidiConnectionState.error);
      return false;
    }
  }

  void _startMidiListening() {
    _midiDataStreamSub?.cancel();

    _midiDataStreamSub =
        _midiCommand.onMidiDataReceived?.listen((packet) {
      _handleMidiPacket(packet.data, packet.device);
    });

    debugPrint('[MidiService] Listening for MIDI events');
  }

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
              : MidiEventType.noteOff;
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
          note = data[1];
          velocity = data[2];
        }
        break;
      case 0xE0: // Pitch Bend
        if (data.length >= 3) {
          eventType = MidiEventType.pitchBend;
          note = data[1] | (data[2] << 7);
          velocity = 0;
        }
        break;
    }

    if (eventType != null) {
      _midiEventController.add(MidiEvent(
        type: eventType,
        note: note,
        velocity: velocity,
        channel: channel,
        source: _connectionType ?? MidiConnectionType.bluetooth,
      ));
    }
  }

  Future<void> sendNoteOn(int note, int velocity, {int channel = 0}) async {
    final data = [0x90 | channel, note.clamp(0, 127), velocity.clamp(0, 127)];
    await _midiCommand.sendData(Uint8List.fromList(data));
  }

  Future<void> sendNoteOff(int note, {int channel = 0}) async {
    final data = [0x80 | channel, note.clamp(0, 127), 0];
    await _midiCommand.sendData(Uint8List.fromList(data));
  }

  Future<void> disconnect() async {
    debugPrint('[MidiService] Disconnecting...');
    _midiDataStreamSub?.cancel();
    _midiDataStreamSub = null;

    if (_connectedDevice != null) {
      try {
        final midiDevices = await _midiCommand.devices;
        if (midiDevices != null) {
          final rawId = _connectedDevice!.id
              .replaceAll('ble_', '')
              .replaceAll('usb_', '');
          for (final d in midiDevices) {
            if (d.id == rawId) {
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
    _connectionType = null;
    _updateState(MidiConnectionState.disconnected);
    debugPrint('[MidiService] Disconnected');
  }

  void _updateState(MidiConnectionState state) {
    _connectionState = state;
    _connectionStateController.add(state);
  }

  void sendTestEvent(MidiEvent event) {
    _midiEventController.add(event);
  }

  void dispose() {
    _midiDataStreamSub?.cancel();
    _deviceDiscoverySub?.cancel();
    _connectionStateController.close();
    _midiEventController.close();
    _devicesController.close();
  }

  // ──────── 工具 ────────

  String? _extractManufacturer(String? name) {
    if (name == null) return null;
    const manufacturers = [
      'Yamaha', 'Roland', 'Kawai', 'Casio', 'Korg', 'Nord', 'Kurzweil'
    ];
    for (final m in manufacturers) {
      if (name.toLowerCase().contains(m.toLowerCase())) return m;
    }
    return null;
  }
}
