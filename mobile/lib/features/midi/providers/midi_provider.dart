import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../midi/services/midi_service.dart';

/// MIDI 连接状态 Provider
final midiConnectionStateProvider = StateProvider<MidiConnectionState>((ref) {
  return MidiConnectionState.disconnected;
});

/// 已连接设备 Provider
final connectedDeviceProvider = StateProvider<MidiDevice?>((ref) {
  return null;
});

/// MIDI 服务 Provider
final midiServiceProvider = Provider<MidiService>((ref) {
  return MidiService();
});

/// 设备列表 Provider
final deviceListProvider = FutureProvider<List<MidiDevice>>((ref) async {
  final midiService = ref.watch(midiServiceProvider);
  return midiService.scanDevices();
});

/// MIDI 状态管理器
class MidiNotifier extends StateNotifier<AsyncValue<void>> {
  final MidiService _midiService;
  final Ref _ref;

  MidiNotifier(this._midiService, this._ref) : super(const AsyncValue.data(null)) {
    _init();
  }

  void _init() {
    // 监听连接状态
    _midiService.connectionState.listen((state) {
      _ref.read(midiConnectionStateProvider.notifier).state = state;
    });
  }

  Future<bool> connect(MidiDevice device) async {
    state = const AsyncValue.loading();
    
    try {
      final success = await _midiService.connect(device);
      if (success) {
        _ref.read(connectedDeviceProvider.notifier).state = 
          _midiService.connectedDevice;
      }
      state = const AsyncValue.data(null);
      return success;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }

  Future<void> disconnect() async {
    await _midiService.disconnect();
    _ref.read(connectedDeviceProvider.notifier).state = null;
  }
}

final midiNotifierProvider = StateNotifierProvider<MidiNotifier, AsyncValue<void>>((ref) {
  final midiService = ref.watch(midiServiceProvider);
  return MidiNotifier(midiService, ref);
});
