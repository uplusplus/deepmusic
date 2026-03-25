import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/midi_service.dart';

/// MIDI 连接状态 Provider
final midiConnectionStateProvider = StreamProvider<MidiConnectionState>((ref) {
  return MidiService().connectionState;
});

/// MIDI 设备列表 Provider
final midiDevicesProvider = StreamProvider<List<MidiDevice>>((ref) {
  return MidiService().devices;
});

/// MIDI 连接信息 Provider
final midiConnectionInfoProvider = Provider<MidiConnectionInfo>((ref) {
  final state = ref.watch(midiConnectionStateProvider).valueOrNull ??
      MidiConnectionState.disconnected;
  final service = MidiService();
  return MidiConnectionInfo(
    state: state,
    deviceName: service.connectedDevice?.name,
    connectionType: service.connectionType,
  );
});

class MidiConnectionInfo {
  final MidiConnectionState state;
  final String? deviceName;
  final MidiConnectionType? connectionType;

  MidiConnectionInfo({
    required this.state,
    this.deviceName,
    this.connectionType,
  });

  bool get isConnected => state == MidiConnectionState.connected;
  String get typeLabel =>
      connectionType == MidiConnectionType.usb ? 'USB' : 'BLE';
}
