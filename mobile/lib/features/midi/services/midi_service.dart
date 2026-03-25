import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  // 缓存上次扫描结果（30秒内复用）
  DateTime? _lastScanTime;
  static const Duration _scanCacheTimeout = Duration(seconds: 30);

  // 保存 flutter_midi_command 原始设备引用（扫描停止后可能丢失，需要缓存）
  final Map<String, dynamic> _rawBleDeviceMap = {};

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
  ///
  /// 30秒内重复调用会返回缓存结果，避免重复扫描
  Future<List<MidiDevice>> scanAllDevices({bool force = false}) async {
    // 如果已在扫描中，等待扫描完成
    if (_connectionState == MidiConnectionState.scanning) {
      debugPrint('[MidiService] Scan already in progress, waiting...');
      await for (final state in _connectionStateController.stream) {
        if (state != MidiConnectionState.scanning) break;
      }
      return List.unmodifiable([..._discoveredUsbDevices, ..._discoveredBleDevices]);
    }

    // 复用缓存结果
    if (!force && _lastScanTime != null) {
      final elapsed = DateTime.now().difference(_lastScanTime!);
      if (elapsed < _scanCacheTimeout) {
        debugPrint('[MidiService] Using cached scan results (${elapsed.inSeconds}s ago)');
        final allDevices = [..._discoveredUsbDevices, ..._discoveredBleDevices];
        _devicesController.add(List.unmodifiable(allDevices));
        return allDevices;
      }
    }

    debugPrint('[MidiService] Scanning all devices...');
    _updateState(MidiConnectionState.scanning);

    // 先停止之前的扫描（如果有）
    try { _midiCommand.stopScanningForBluetoothDevices(); } catch (_) {}

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
    _lastScanTime = DateTime.now();

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

      // 不停止扫描 —— stopScanning 会清空设备列表，导致后续连接找不到设备
      // 扫描会在连接时由 _connectBleDevice 停止，或由 disconnect/dispose 停止
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
        _rawBleDeviceMap.clear();
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
          final deviceId = 'ble_${device.id}';

          // 缓存原始设备引用，供连接时使用（stopScanning 后 devices 列表可能清空）
          _rawBleDeviceMap[deviceId] = device;

          _discoveredBleDevices.add(MidiDevice(
            id: deviceId,
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

  /// 连接设备，失败时返回具体错误信息
  /// 成功返回 null，失败返回错误消息
  String? _lastConnectError;

  String? get lastConnectError => _lastConnectError;

  Future<bool> connect(MidiDevice device) async {
    debugPrint('[MidiService] Connecting to ${device.name} (id=${device.id}, type=${device.connectionType.name})...');
    _updateState(MidiConnectionState.connecting);
    _reconnectAttempts = 0;
    _lastConnectError = null;

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
        // 保存到已知设备
        _saveKnownDevice(device);
        return true;
      } else {
        _lastConnectError = '连接失败，请重试';
        _updateState(MidiConnectionState.error);
        return false;
      }
    } catch (e) {
      debugPrint('[MidiService] Connection failed: $e');
      _lastConnectError = e.toString().replaceFirst('Exception: ', '');
      _updateState(MidiConnectionState.error);
      return false;
    }
  }

  Future<bool> _connectBleDevice(MidiDevice device) async {
    try {
      // 1. 确保 BLE Central 已初始化
      await _midiCommand.startBluetoothCentral();
      await _midiCommand.waitUntilBluetoothIsInitialized();

      // 2. 获取当前设备列表（扫描仍在运行，设备列表有效）
      final midiDevices = await _midiCommand.devices;
      debugPrint('[MidiService] BLE connect: available devices=${midiDevices?.length ?? 0}');

      if (midiDevices == null || midiDevices.isEmpty) {
        throw Exception('设备列表为空，请先扫描设备');
      }

      // 打印所有可用设备（调试用）
      for (final d in midiDevices) {
        debugPrint('[MidiService] BLE connect:   - ${d.name}(${d.id}) connected=${d.connected}');
      }

      // 3. 查找目标设备
      final rawId = device.id.replaceAll('ble_', '');
      dynamic targetDevice;
      for (final d in midiDevices) {
        if (d.id == rawId) {
          final name = d.name ?? '';
          if (name == 'MidiManager' || name == '-' || name.isEmpty) continue;
          targetDevice = d;
          break;
        }
      }

      if (targetDevice == null) {
        throw Exception('设备 "${device.name}" 不在当前列表中，请重新扫描');
      }

      // 4. 直接在扫描状态下连接（不要停止扫描！stopScanning 会清空设备列表）
      debugPrint('[MidiService] BLE connect: connecting to ${targetDevice.name}...');
      await _midiCommand.connectToDevice(targetDevice).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw Exception('连接超时（15s），请确认设备已开启蓝牙配对模式');
        },
      );

      // 连接成功后停止扫描
      _midiCommand.stopScanningForBluetoothDevices();
      debugPrint('[MidiService] BLE connect: connectToDevice succeeded');
      _startBleMidiListening();
      return true;
    } catch (e) {
      debugPrint('[MidiService] BLE connect failed: $e');
      rethrow;
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

    // 停止 BLE 扫描
    try { _midiCommand.stopScanningForBluetoothDevices(); } catch (_) {}

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

  // ──────── 已知设备自动连接 ────────

  static const String _knownDevicesKey = 'midi_known_devices';

  /// 连接成功后保存到已知设备列表
  Future<void> _saveKnownDevice(MidiDevice device) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final known = await _loadKnownDevices();

      // 去重：按名称匹配（同一台琴 BLE 和 USB 名称相同）
      known.removeWhere((d) => d['name'] == device.name);
      known.add({
        'name': device.name,
        'type': device.connectionType.name,
        'lastConnected': DateTime.now().toIso8601String(),
      });

      // 最多保留 10 个
      while (known.length > 10) {
        known.removeAt(0);
      }

      await prefs.setString(_knownDevicesKey, jsonEncode(known));
      debugPrint('[MidiService] Saved known device: ${device.name}');
    } catch (e) {
      debugPrint('[MidiService] Save known device failed: $e');
    }
  }

  /// 从 SharedPreferences 加载已知设备列表
  Future<List<Map<String, dynamic>>> _loadKnownDevices() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_knownDevicesKey);
      if (raw == null || raw.isEmpty) return [];
      final list = jsonDecode(raw) as List;
      return list.cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('[MidiService] Load known devices failed: $e');
      return [];
    }
  }

  /// 自动连接：扫描发现已知设备后自动连接（信号最强优先）
  ///
  /// 返回是否成功连接
  Future<bool> autoConnect() async {
    if (_connectionState == MidiConnectionState.connected) return true;
    if (_connectionState == MidiConnectionState.connecting) return false;

    debugPrint('[MidiService] Auto-connect: scanning...');
    final knownDevices = await _loadKnownDevices();
    if (knownDevices.isEmpty) {
      debugPrint('[MidiService] Auto-connect: no known devices');
      return false;
    }

    final knownNames = knownDevices.map((d) => d['name'] as String).toSet();
    debugPrint('[MidiService] Auto-connect: known devices = $knownNames');

    // 扫描所有设备
    final scanned = await scanAllDevices();

    // 找到已知设备（按最近连接时间排序，最新的优先）
    knownDevices.sort((a, b) {
      final ta = DateTime.tryParse(a['lastConnected'] ?? '') ?? DateTime(2000);
      final tb = DateTime.tryParse(b['lastConnected'] ?? '') ?? DateTime(2000);
      return tb.compareTo(ta); // 最近连接的排前面
    });

    for (final known in knownDevices) {
      final name = known['name'] as String;
      final match = scanned.where((d) => d.name == name).toList();
      if (match.isNotEmpty) {
        debugPrint('[MidiService] Auto-connect: found known device "$name", connecting...');
        final success = await connect(match.first);
        if (success) {
          debugPrint('[MidiService] Auto-connect: connected to $name');
          return true;
        }
        debugPrint('[MidiService] Auto-connect: failed to connect to $name, trying next...');
      }
    }

    debugPrint('[MidiService] Auto-connect: no known device found in scan');
    _updateState(
      _connectedDevice != null
          ? MidiConnectionState.connected
          : MidiConnectionState.disconnected,
    );
    return false;
  }

  void _updateState(MidiConnectionState state) {
    _connectionState = state;
    _connectionStateController.add(state);
  }

  void sendTestEvent(MidiEvent event) {
    _midiEventController.add(event);
  }

  void sendNoteOn(int note, int velocity, {int channel = 0}) {
    // MIDI Note On: status=0x90|channel, data1=note, data2=velocity
    final statusByte = 0x90 | (channel & 0x0F);
    final data = Uint8List.fromList([statusByte, note & 0x7F, velocity & 0x7F]);
    _sendMidiData(data);
    debugPrint('[MidiService] sendNoteOn: note=$note, velocity=$velocity, ch=$channel');
  }

  void sendNoteOff(int note, {int channel = 0}) {
    // MIDI Note Off: status=0x80|channel, data1=note, data2=0
    final statusByte = 0x80 | (channel & 0x0F);
    final data = Uint8List.fromList([statusByte, note & 0x7F, 0x00]);
    _sendMidiData(data);
    debugPrint('[MidiService] sendNoteOff: note=$note, ch=$channel');
  }

  /// 发送 MIDI Control Change
  void sendControlChange(int controller, int value, {int channel = 0}) {
    final statusByte = 0xB0 | (channel & 0x0F);
    final data = Uint8List.fromList([statusByte, controller & 0x7F, value & 0x7F]);
    _sendMidiData(data);
    debugPrint('[MidiService] sendCC: cc=$controller, value=$value, ch=$channel');
  }

  /// 发送原始 MIDI 数据到已连接的设备
  void _sendMidiData(Uint8List data) {
    if (_connectedDevice == null) {
      debugPrint('[MidiService] No device connected, skipping MIDI send');
      return;
    }

    if (_connectionType == MidiConnectionType.bluetooth) {
      _sendBleMidiData(data);
    } else if (_connectionType == MidiConnectionType.usb) {
      _sendUsbMidiData(data);
    }
  }

  /// 通过 BLE 发送 MIDI 数据
  void _sendBleMidiData(Uint8List data) {
    try {
      // flutter_midi_command 的 sendData 方法
      _midiCommand.sendData(data);
    } catch (e) {
      debugPrint('[MidiService] BLE send failed: $e');
    }
  }

  /// 通过 USB 发送 MIDI 数据
  /// USB MIDI 包格式: [Cable Number | Code Index Number, MIDI_0, MIDI_1, MIDI_2]
  void _sendUsbMidiData(Uint8List data) {
    if (_usbPort == null) return;

    try {
      // 将标准 MIDI 消息打包为 USB MIDI 包
      final packets = <int>[];
      int offset = 0;

      while (offset < data.length) {
        final statusByte = data[offset];
        final messageType = statusByte & 0xF0;
        int cin; // Code Index Number

        switch (messageType) {
          case 0x80: // Note Off (3 bytes)
          case 0x90: // Note On (3 bytes)
          case 0xA0: // Polyphonic Aftertouch (3 bytes)
          case 0xB0: // Control Change (3 bytes)
          case 0xE0: // Pitch Bend (3 bytes)
            cin = messageType >> 4;
            if (offset + 2 < data.length) {
              packets.addAll([cin, data[offset], data[offset + 1], data[offset + 2]]);
              offset += 3;
            } else {
              offset = data.length; // 数据不足，终止
            }
            break;
          case 0xC0: // Program Change (2 bytes)
          case 0xD0: // Channel Aftertouch (2 bytes)
            cin = messageType >> 4;
            if (offset + 1 < data.length) {
              packets.addAll([cin, data[offset], data[offset + 1], 0x00]);
              offset += 2;
            } else {
              offset = data.length;
            }
            break;
          case 0xF0: // System messages
            cin = 0x5; // Single Byte / SysEx ends
            packets.addAll([cin, data[offset], 0x00, 0x00]);
            offset += 1;
            break;
          default:
            // 未知，跳过
            offset += 1;
            break;
        }
      }

      if (packets.isNotEmpty) {
        _usbPort!.write(Uint8List.fromList(packets));
      }
    } catch (e) {
      debugPrint('[MidiService] USB send failed: $e');
    }
  }

  void dispose() {
    try { _midiCommand.stopScanningForBluetoothDevices(); } catch (_) {}
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
