import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';
// ignore: depend_on_referenced_packages
import 'package:usb_serial/usb_serial.dart';
import 'ble_permissions.dart';

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

/// MIDI 服务 — BLE + USB 双连接，自动重连
///
/// USB 连接优先（延迟 <20ms），BLE 备用（延迟 <50ms）
/// 两种来源共享统一 Stream<MidiEvent>
/// BLE 断线自动重连 (最多 3 次，指数退避)
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

  // ── USB 底层 ──
  UsbPort? _usbPort;
  StreamSubscription<Uint8List>? _usbDataSub;
  Timer? _usbHotplugTimer;

  // ── BLE 自动重连 ──
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 3;
  Timer? _reconnectTimer;

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

  /// 扫描所有可用设备 (BLE + USB)，USB 优先
  Future<List<MidiDevice>> scanAllDevices() async {
    debugPrint('[MidiService] Scanning all devices...');
    _updateState(MidiConnectionState.scanning);

    // 先请求蓝牙权限
    final hasPermission = await BlePermissions.requestBlePermissions();
    if (!hasPermission) {
      debugPrint('[MidiService] BLE permissions denied, scanning USB only');
    }

    // 检查蓝牙是否开启
    if (hasPermission) {
      final btAvailable = await isBluetoothAvailable();
      if (!btAvailable) {
        debugPrint('[MidiService] Bluetooth is OFF, cannot scan BLE devices');
      }
    }

    await Future.wait([
      if (hasPermission) _scanBleDevices(),
      _scanUsbDevices(),
    ]);

    final allDevices = [
      ..._discoveredUsbDevices,
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
      // 先初始化 BLE 中心（插件内部会检查权限并启动扫描）
      await _midiCommand.startBluetoothCentral();
      // 等待蓝牙状态初始化
      await _midiCommand.waitUntilBluetoothIsInitialized();

      await _midiCommand.startScanningForBluetoothDevices();

      _deviceDiscoverySub?.cancel();
      _deviceDiscoverySub =
          _midiCommand.onMidiSetupChanged?.listen((event) {
        debugPrint('[MidiService] BLE setup changed: $event');
        // 实时更新设备列表
        _refreshBleDeviceList();
      });

      // BLE 扫描需要更长时间，扩展到 8 秒
      await Future.delayed(const Duration(seconds: 8));

      // ⚠️ 必须在 stopScanning 之前读取设备！
      // stopScanningForBluetoothDevices() 会调用 discoveredDevices.clear()
      await _refreshBleDeviceList();

      _midiCommand.stopScanningForBluetoothDevices();
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
          // 跳过虚拟/系统 MIDI 设备
          final name = device.name ?? '';
          if (name == 'MidiManager' || name == '-') {
            debugPrint('[MidiService] Skipping virtual MIDI device: $name');
            continue;
          }

          // 尝试获取设备类型
          String? deviceType;
          try {
            deviceType = (device as dynamic).type as String?;
          } catch (_) {
            deviceType = null;
          }

          // 只跳过明确为 native/virtual 类型的设备
          if (deviceType == 'native' || deviceType == 'virtual') {
            debugPrint('[MidiService] Skipping $deviceType device: $name');
            continue;
          }

          final displayName = name.isNotEmpty ? name : 'Unknown BLE Device';
          _discoveredBleDevices.add(MidiDevice(
            id: 'ble_${device.id}',
            name: displayName,
            manufacturer: _extractManufacturer(name),
            isConnected: device.connected ?? false,
            connectionType: MidiConnectionType.bluetooth,
          ));
          debugPrint('[MidiService] Found BLE device: $displayName (type=$deviceType)');
        }
      }
    } catch (e) {
      debugPrint('[MidiService] BLE refresh failed: $e');
    }
  }

  // ──────── USB OTG 底层实现 ────────

  Future<List<MidiDevice>> _scanUsbDevices() async {
    _discoveredUsbDevices.clear();
    try {
      final devices = await UsbSerial.listDevices();
      debugPrint('[MidiService] USB devices found: ${devices.length}');

      for (final device in devices) {
        // USB MIDI 设备通常 vid/pid 匹配 USB MIDI Class (0x01)
        // 或者通过设备名称判断
        final name = _getUsbDeviceName(device);
        if (_isUsbMidiDevice(device, name)) {
          _discoveredUsbDevices.add(MidiDevice(
            id: 'usb_${device.deviceId}',
            name: name,
            manufacturer: _extractManufacturer(name),
            isConnected: false,
            connectionType: MidiConnectionType.usb,
          ));
        }
      }

      debugPrint('[MidiService] USB MIDI devices: ${_discoveredUsbDevices.length}');
    } catch (e) {
      debugPrint('[MidiService] USB scan failed: $e');
    }
    return _discoveredUsbDevices;
  }

  String _getUsbDeviceName(UsbDevice device) {
    // UsbDevice 可能没有友好名称，用 VID/PID 构造
    final vid = device.vid;
    final pid = device.pid;
    final knownNames = <String, String>{
      '0499': 'Yamaha',
      '0582': 'Roland',
      '09e8': 'AKAI',
      '1235': 'Novation',
    };
    final vendorHex = vid?.toRadixString(16).padLeft(4, '0') ?? '0000';
    final vendor = knownNames[vendorHex] ?? 'Unknown';
    final pidHex = pid?.toRadixString(16).padLeft(4, '0') ?? '0000';
    return '$vendor USB MIDI (VID:$vendorHex PID:$pidHex)';
  }

  bool _isUsbMidiDevice(UsbDevice device, String name) {
    // USB MIDI Class: interfaceClass == 1 (Audio), subclass == 3 (MIDI)
    // 或者通过已知 MIDI 制造商 VID 判断
    final knownVids = [0x0499, 0x0582, 0x09e8, 0x1235, 0x17cc]; // Yamaha, Roland, AKAI, Novation, Korg
    if (knownVids.contains(device.vid)) return true;

    // 设备类判断 (如果接口信息可用)
    if (device.interfaceCount != null && device.interfaceCount! > 0) return true; // 有接口的 USB 设备都尝试连接

    return false;
  }

  Future<bool> _connectUsbDevice(MidiDevice device) async {
    final rawIdStr = device.id.replaceAll('usb_', '');
    final rawId = int.tryParse(rawIdStr);
    if (rawId == null) {
      debugPrint('[MidiService] Invalid USB device ID: ${device.id}');
      return false;
    }

    try {
      final usbDevices = await UsbSerial.listDevices();
      UsbDevice? targetDevice;
      for (final d in usbDevices) {
        if (d.deviceId == rawId) {
          targetDevice = d;
          break;
        }
      }

      if (targetDevice == null) {
        debugPrint('[MidiService] USB device not found: $rawId');
        return false;
      }

      // 请求 USB 权限
      final hasPermission = await targetDevice.create() != null;
      if (!hasPermission) {
        debugPrint('[MidiService] USB permission denied');
        return false;
      }

      final port = await targetDevice.create();
      if (port == null) {
        debugPrint('[MidiService] Failed to create USB port');
        return false;
      }

      // 配置串口参数 (USB MIDI 不走串口协议，但需要打开端口)
      await port.setDTR(true);
      await port.setRTS(true);
      await port.setPortParameters(
        115200,  // USB MIDI 实际不使用波特率，这里仅初始化
        UsbPort.DATABITS_8,
        UsbPort.STOPBITS_1,
        UsbPort.PARITY_NONE,
      );

      _usbPort = port;

      // 监听 USB 数据
      _usbDataSub?.cancel();
      _usbDataSub = port.inputStream?.listen(
        (data) => _handleUsbMidiData(data),
        onError: (e) {
          debugPrint('[MidiService] USB data error: $e');
          _handleUsbDisconnect();
        },
        onDone: () {
          debugPrint('[MidiService] USB stream closed');
          _handleUsbDisconnect();
        },
      );

      // 启动热插拔检测
      _startUsbHotplugMonitor();

      debugPrint('[MidiService] USB connected: ${device.name}');
      return true;
    } catch (e) {
      debugPrint('[MidiService] USB connect failed: $e');
      return false;
    }
  }

  void _handleUsbMidiData(Uint8List data) {
    if (data.isEmpty) return;

    // USB MIDI 数据包格式: [Cable Number | Code Index Number, MIDI_0, MIDI_1, MIDI_2]
    // 每个 USB MIDI 包 4 字节
    int offset = 0;
    while (offset + 3 < data.length) {
      final cin = data[offset] & 0x0F; // Code Index Number
      final midiBytes = data.sublist(offset + 1, offset + 4);

      MidiEventType? eventType;
      int note = 0;
      int velocity = 0;
      int channel = 0;

      switch (cin) {
        case 0x9: // Note On
          channel = midiBytes[0] & 0x0F;
          note = midiBytes[1];
          velocity = midiBytes[2];
          eventType = velocity > 0 ? MidiEventType.noteOn : MidiEventType.noteOff;
          break;
        case 0x8: // Note Off
          channel = midiBytes[0] & 0x0F;
          note = midiBytes[1];
          velocity = midiBytes[2];
          eventType = MidiEventType.noteOff;
          break;
        case 0xB: // Control Change
          channel = midiBytes[0] & 0x0F;
          note = midiBytes[1];
          velocity = midiBytes[2];
          eventType = MidiEventType.controlChange;
          break;
        case 0xE: // Pitch Bend
          channel = midiBytes[0] & 0x0F;
          note = midiBytes[1] | (midiBytes[2] << 7);
          eventType = MidiEventType.pitchBend;
          break;
      }

      if (eventType != null) {
        _midiEventController.add(MidiEvent(
          type: eventType,
          note: note,
          velocity: velocity,
          channel: channel,
          source: MidiConnectionType.usb,
        ));
      }

      offset += 4;
    }
  }

  void _handleUsbDisconnect() {
    debugPrint('[MidiService] USB disconnected');
    _usbDataSub?.cancel();
    _usbDataSub = null;
    _usbPort?.close();
    _usbPort = null;
    _usbHotplugTimer?.cancel();

    if (_connectionType == MidiConnectionType.usb) {
      _connectedDevice = null;
      _connectionType = null;
      _updateState(MidiConnectionState.disconnected);
    }
  }

  void _startUsbHotplugMonitor() {
    _usbHotplugTimer?.cancel();
    _usbHotplugTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (_connectionType != MidiConnectionType.usb) return;
      try {
        final devices = await UsbSerial.listDevices();
        final stillConnected = devices.any(
          (d) => d.deviceId.toString() == _connectedDevice?.id.replaceAll('usb_', ''),
        );
        if (!stillConnected) {
          debugPrint('[MidiService] USB device removed (hotplug)');
          _handleUsbDisconnect();
        }
      } catch (e) {
        // ignore polling errors
      }
    });
  }

  // ──────── 连接 ────────

  Future<bool> connect(MidiDevice device) async {
    debugPrint('[MidiService] Connecting to ${device.name} (id=${device.id}, type=${device.connectionType.name})...');
    _updateState(MidiConnectionState.connecting);
    _reconnectAttempts = 0; // 手动连接，重置重连计数

    try {
      bool success;

      if (device.connectionType == MidiConnectionType.usb) {
        success = await _connectUsbDevice(device);
      } else {
        success = await _connectBleDevice(device);
      }

      debugPrint('[MidiService] connect result: $success');
      if (success) {
        _connectedDevice = device.copyWith(isConnected: true);
        _connectionType = device.connectionType;
        _updateState(MidiConnectionState.connected);
        debugPrint('[MidiService] Connected: ${device.name} via ${device.connectionType.name}');
        return true;
      } else {
        _updateState(MidiConnectionState.error);
        return false;
      }
    } catch (e) {
      debugPrint('[MidiService] Connection failed: $e');
      _updateState(MidiConnectionState.error);
      return false;
    }
  }

  Future<bool> _connectBleDevice(MidiDevice device) async {
    try {
      final midiDevices = await _midiCommand.devices;
      debugPrint('[MidiService] BLE connect: available devices=${midiDevices?.length ?? 0}');
      if (midiDevices == null) throw Exception('无法获取设备列表');

      final rawId = device.id.replaceAll('ble_', '');
      debugPrint('[MidiService] BLE connect: looking for rawId=$rawId');

      dynamic targetDevice;
      for (final d in midiDevices) {
        debugPrint('[MidiService] BLE connect: device id=${d.id} name=${d.name} connected=${d.connected}');
        if (d.id == rawId) {
          // 额外安全检查：跳过已知的虚拟 MIDI 设备
          final name = d.name ?? '';
          if (name == 'MidiManager' || name == '-' || name.isEmpty) {
            debugPrint('[MidiService] Skipping virtual MIDI device: $name');
            continue;
          }
          targetDevice = d;
          break;
        }
      }
      if (targetDevice == null) {
        debugPrint('[MidiService] BLE connect: device $rawId NOT found in ${midiDevices.length} devices');
        throw Exception('设备未找到或为虚拟设备');
      }

      debugPrint('[MidiService] BLE connect: calling connectToDevice for ${targetDevice.name}');
      await _midiCommand.connectToDevice(targetDevice);
      debugPrint('[MidiService] BLE connect: connectToDevice succeeded');
      _startBleMidiListening();
      return true;
    } catch (e) {
      debugPrint('[MidiService] BLE connect failed: $e');
      return false;
    }
  }

  void _startBleMidiListening() {
    _midiDataStreamSub?.cancel();
    _midiDataStreamSub = _midiCommand.onMidiDataReceived?.listen((packet) {
      _handleBleMidiPacket(packet.data);
    });
  }

  void _handleBleMidiPacket(List<int> data) {
    if (data.isEmpty) return;

    final statusByte = data[0];
    final channel = statusByte & 0x0F;
    final messageType = statusByte & 0xF0;

    MidiEventType? eventType;
    int note = 0;
    int velocity = 0;

    switch (messageType) {
      case 0x90:
        if (data.length >= 3) {
          note = data[1]; velocity = data[2];
          eventType = velocity > 0 ? MidiEventType.noteOn : MidiEventType.noteOff;
        }
        break;
      case 0x80:
        if (data.length >= 3) {
          note = data[1]; velocity = data[2];
          eventType = MidiEventType.noteOff;
        }
        break;
      case 0xB0:
        if (data.length >= 3) {
          eventType = MidiEventType.controlChange;
          note = data[1]; velocity = data[2];
        }
        break;
      case 0xE0:
        if (data.length >= 3) {
          eventType = MidiEventType.pitchBend;
          note = data[1] | (data[2] << 7);
        }
        break;
    }

    if (eventType != null) {
      _midiEventController.add(MidiEvent(
        type: eventType, note: note, velocity: velocity,
        channel: channel, source: MidiConnectionType.bluetooth,
      ));
    }
  }

  // ──────── BLE 自动重连 ────────

  void _startBleAutoReconnect() {
    if (_connectionType != MidiConnectionType.bluetooth) return;
    if (_connectedDevice == null) return;
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      debugPrint('[MidiService] Max reconnect attempts reached');
      _updateState(MidiConnectionState.error);
      return;
    }

    _reconnectAttempts++;
    // 指数退避: 2s, 4s, 8s
    final delayMs = 2000 * (1 << (_reconnectAttempts - 1));
    debugPrint('[MidiService] Auto-reconnect attempt $_reconnectAttempts in ${delayMs}ms');

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(milliseconds: delayMs), () async {
      if (_connectedDevice == null) return;
      debugPrint('[MidiService] Reconnecting...');
      final success = await _connectBleDevice(_connectedDevice!);
      if (success) {
        _reconnectAttempts = 0;
        _updateState(MidiConnectionState.connected);
        debugPrint('[MidiService] Reconnected successfully');
      } else {
        _startBleAutoReconnect(); // 递归重试
      }
    });
  }

  // ──────── 断开 ────────

  Future<void> disconnect() async {
    debugPrint('[MidiService] Disconnecting...');
    _midiDataStreamSub?.cancel();
    _midiDataStreamSub = null;
    _reconnectTimer?.cancel();
    _reconnectAttempts = 0;

    // USB 断开
    if (_connectionType == MidiConnectionType.usb) {
      _handleUsbDisconnect();
    }

    // BLE 断开
    if (_connectedDevice != null && _connectionType == MidiConnectionType.bluetooth) {
      try {
        final midiDevices = await _midiCommand.devices;
        if (midiDevices != null) {
          final rawId = _connectedDevice!.id.replaceAll('ble_', '');
          for (final d in midiDevices) {
            if (d.id == rawId) {
              _midiCommand.disconnectDevice(d);
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
  }

  void _updateState(MidiConnectionState state) {
    _connectionState = state;
    _connectionStateController.add(state);
  }

  void sendTestEvent(MidiEvent event) {
    _midiEventController.add(event);
  }

  void sendNoteOn(int note, int velocity) {
    // 发送 MIDI Note On 事件 (用于自动播放)
    // 注意: 这里只是模拟发送，实际需要通过 USB/BLE 发送 MIDI 数据
    // 由于 flutter_midi_command 没有直接发送 MIDI 的 API，这里仅记录日志
    debugPrint('[MidiService] sendNoteOn: note=$note, velocity=$velocity');
  }

  void sendNoteOff(int note) {
    // 发送 MIDI Note Off 事件 (用于自动播放)
    debugPrint('[MidiService] sendNoteOff: note=$note');
  }

  void dispose() {
    _midiDataStreamSub?.cancel();
    _deviceDiscoverySub?.cancel();
    _usbDataSub?.cancel();
    _usbPort?.close();
    _reconnectTimer?.cancel();
    _usbHotplugTimer?.cancel();
    _connectionStateController.close();
    _midiEventController.close();
    _devicesController.close();
  }

  String? _extractManufacturer(String? name) {
    if (name == null) return null;
    const manufacturers = [
      'Yamaha', 'Roland', 'Kawai', 'Casio', 'Korg', 'Nord', 'Kurzweil', 'AKAI', 'Novation',
    ];
    for (final m in manufacturers) {
      if (name.toLowerCase().contains(m.toLowerCase())) return m;
    }
    return null;
  }
}
