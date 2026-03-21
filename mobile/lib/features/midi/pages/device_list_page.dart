import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../services/midi_service.dart';

class DeviceListPage extends ConsumerStatefulWidget {
  const DeviceListPage({super.key});

  @override
  ConsumerState<DeviceListPage> createState() => _DeviceListPageState();
}

class _DeviceListPageState extends ConsumerState<DeviceListPage> {
  final MidiService _midiService = MidiService();
  List<MidiDevice> _devices = [];
  bool _isScanning = false;
  StreamSubscription? _devicesSub;
  StreamSubscription? _stateSub;
  MidiConnectionState _connectionState = MidiConnectionState.disconnected;

  @override
  void initState() {
    super.initState();
    _listenToDevices();
    _startScan();
  }

  void _listenToDevices() {
    _devicesSub = _midiService.devices.listen((devices) {
      if (mounted) setState(() => _devices = devices);
    });

    _stateSub = _midiService.connectionState.listen((state) {
      if (mounted) setState(() => _connectionState = state);
    });

    // 如果已有缓存设备，立即显示
    final current = _midiService.currentState;
    if (current != MidiConnectionState.scanning) {
      // 用已有的设备流数据填充
    }
  }

  Future<void> _startScan({bool force = false}) async {
    setState(() => _isScanning = true);
    final devices = await _midiService.scanAllDevices(force: force);
    if (mounted) {
      setState(() {
        _devices = devices;
        _isScanning = false;
      });
    }
  }

  bool _isConnecting = false;

  Future<void> _connectToDevice(MidiDevice device) async {
    if (_isConnecting) return;
    setState(() => _isConnecting = true);
    try {
      final success = await _midiService.connect(device);
      if (mounted) {
        final errorMsg = _midiService.lastConnectError;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? '已连接 ${device.name}' : (errorMsg ?? '连接失败')),
            backgroundColor: success ? AppColors.success : AppColors.error,
            duration: Duration(seconds: success ? 2 : 4),
          ),
        );
        if (success) Navigator.pop(context);
      }
    } finally {
      if (mounted) setState(() => _isConnecting = false);
    }
  }

  @override
  void dispose() {
    _devicesSub?.cancel();
    _stateSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final usbDevices = _devices
        .where((d) => d.connectionType == MidiConnectionType.usb)
        .toList();
    final bleDevices = _devices
        .where((d) => d.connectionType == MidiConnectionType.bluetooth)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('MIDI 设备'),
        actions: [
          IconButton(
            icon: _isScanning
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            onPressed: _isScanning ? null : () => _startScan(force: true),
          ),
        ],
      ),
      body: Column(
        children: [
          // 连接状态
          _buildConnectionStatus(),
          Expanded(
            child: _devices.isEmpty && !_isScanning
                ? _buildEmptyState()
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (usbDevices.isNotEmpty) ...[
                        _buildSectionHeader('USB 连接', Icons.usb),
                        ...usbDevices.map(_buildDeviceTile),
                        const SizedBox(height: 16),
                      ],
                      if (bleDevices.isNotEmpty) ...[
                        _buildSectionHeader('蓝牙连接', Icons.bluetooth),
                        ...bleDevices.map(_buildDeviceTile),
                      ],
                      if (_isScanning && _devices.isEmpty)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(32),
                            child: CircularProgressIndicator(),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionStatus() {
    Color color;
    String text;
    IconData icon;

    switch (_connectionState) {
      case MidiConnectionState.connected:
        color = AppColors.success;
        final device = _midiService.connectedDevice;
        final typeLabel =
            device?.connectionType == MidiConnectionType.usb ? 'USB' : 'BLE';
        text = '已连接 ($typeLabel): ${device?.name ?? "未知"}';
        icon = Icons.check_circle;
        break;
      case MidiConnectionState.connecting:
        color = AppColors.warning;
        text = '连接中...';
        icon = Icons.hourglass_empty;
        break;
      case MidiConnectionState.error:
        color = AppColors.error;
        text = '连接错误';
        icon = Icons.error;
        break;
      default:
        color = Colors.grey;
        text = '未连接';
        icon = Icons.circle_outlined;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      color: color.withOpacity(0.08),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
              child: Text(text, style: TextStyle(color: color, fontSize: 13))),
          if (_connectionState == MidiConnectionState.connected)
            TextButton(
              onPressed: _midiService.disconnect,
              child: const Text('断开'),
            ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 6),
          Text(title,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildDeviceTile(MidiDevice device) {
    final isConnected = _midiService.connectedDevice?.id == device.id;
    final isUsb = device.connectionType == MidiConnectionType.usb;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isConnected
              ? AppColors.success.withOpacity(0.1)
              : Colors.grey.withOpacity(0.1),
          child: Icon(
            isUsb ? Icons.usb : Icons.bluetooth,
            color: isConnected ? AppColors.success : Colors.grey,
          ),
        ),
        title: Text(device.name),
        subtitle: Text(
          [
            if (device.manufacturer != null) device.manufacturer!,
            isUsb ? 'USB OTG' : '蓝牙 BLE',
            if (isConnected) '· 已连接',
          ].join(' · '),
          style: const TextStyle(fontSize: 12),
        ),
        trailing: isConnected
            ? const Icon(Icons.check_circle, color: AppColors.success)
            : _isConnecting
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : ElevatedButton(
                    onPressed: () => _connectToDevice(device),
                style: ElevatedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  textStyle: const TextStyle(fontSize: 13),
                ),
                child: const Text('连接'),
              ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.piano, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          const Text(
            '未发现 MIDI 设备',
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          const Text(
            '请确保数字钢琴已开启\n蓝牙模式或 USB OTG 已连接',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => _startScan(force: true),
            icon: const Icon(Icons.refresh),
            label: const Text('重新扫描'),
          ),
        ],
      ),
    );
  }
}
