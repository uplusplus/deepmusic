import 'package:flutter/services.dart';
import 'volume_service.dart';

class VolumeMethodChannel {
  static const MethodChannel _channel = MethodChannel('deepmusic/device_info');

  static void init() {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'volumeUp':
          await VolumeService().adjustVolume(0.05);
          break;
        case 'volumeDown':
          await VolumeService().adjustVolume(-0.05);
          break;
        default:
          // ignore unknown calls
          break;
      }
    });
  }
}
