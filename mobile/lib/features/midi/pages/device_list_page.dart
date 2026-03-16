import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/midi_provider.dart';
import '../../../core/constants/app_colors.dart';

class DeviceListPage extends ConsumerStatefulWidget {
  const DeviceListPage({super.key});

  @override
  ConsumerState<DeviceListPage> createState() => _DeviceListPageState();
}

class _DeviceListPageState extends ConsumerState<DeviceListPage> {
  @override
  void initState() {
    super.initState();
    // 初始化时扫描设备
    Future.microtask(() {
      ref.refresh(deviceListProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final devicesAsync = ref.watch(deviceListProvider);
    final connectionState = ref.watch(midiConnectionStateProvider);
    final connectedDevice = ref.watch(connectedDeviceProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('MIDI 设备'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.refresh(deviceListProvider),
          ),
        ],
      ),
      body: Column(
        children: [
          // 连接状态卡片
          _buildConnectionStatus(connectionState, connectedDevice),
          
          // 设备列表
          Expanded(
            child: devicesAsync.when(
              data: (devices) => _buildDeviceList(devices, connectedDevice),
              loading: () => const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('正在扫描设备...'),
                  ],
                ),
              ),
              error: (error, stack) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, size: 48, color: AppColors.error),
                    const SizedBox(height: 16),
                    Text('扫描失败: $error'),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => ref.refresh(deviceListProvider),
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionStatus(
    MidiConnectionState state, 
    MidiDevice? device,
  ) {
    Color statusColor;
    String statusText;
    IconData statusIcon;

    switch (state) {
      case MidiConnectionState.connected:
        statusColor = AppColors.success;
        statusText = '已连接: ${device?.name ?? "未知设备"}';
        statusIcon = Icons.bluetooth_connected;
        break;
      case MidiConnectionState.connecting:
        statusColor = AppColors.warning;
        statusText = '正在连接...';
        statusIcon = Icons.bluetooth_searching;
        break;
      case MidiConnectionState.error:
        statusColor = AppColors.error;
        statusText = '连接失败';
        statusIcon = Icons.bluetooth_disabled;
        break;
      case MidiConnectionState.disconnected:
      default:
        statusColor = AppColors.textSecondary;
        statusText = '未连接';
        statusIcon = Icons.bluetooth;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: statusColor.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(statusIcon, color: statusColor),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              statusText,
              style: TextStyle(
                color: statusColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (state == MidiConnectionState.connected)
            TextButton(
              onPressed: () => ref.read(midiNotifierProvider.notifier).disconnect(),
              child: const Text('断开连接'),
            ),
        ],
      ),
    );
  }

  Widget _buildDeviceList(List<MidiDevice> devices, MidiDevice? connectedDevice) {
    if (devices.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bluetooth_disabled, size: 64, color: AppColors.textHint),
            SizedBox(height: 16),
            Text(
              '未发现 MIDI 设备',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            SizedBox(height: 8),
            Text(
              '请确保设备已开启蓝牙',
              style: TextStyle(color: AppColors.textHint, fontSize: 12),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: devices.length,
      itemBuilder: (context, index) {
        final device = devices[index];
        final isConnected = connectedDevice?.id == device.id;

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: Icon(
              Icons.piano,
              color: isConnected ? AppColors.primary : null,
            ),
            title: Text(device.name),
            subtitle: Text(device.manufacturer ?? '未知厂商'),
            trailing: isConnected
                ? const Icon(Icons.check_circle, color: AppColors.success)
                : const Icon(Icons.chevron_right),
            onTap: isConnected
                ? null
                : () => _connectDevice(device),
          ),
        );
      },
    );
  }

  Future<void> _connectDevice(MidiDevice device) async {
    final success = await ref.read(midiNotifierProvider.notifier).connect(device);
    
    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已连接到 ${device.name}'),
            backgroundColor: AppColors.success,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('连接失败，请重试'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }
}
