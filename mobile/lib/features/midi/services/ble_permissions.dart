import 'dart:io';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// Android 12+ (API 31+) 蓝牙权限工具
class BlePermissions {
  static const _platform = MethodChannel('deepmusic/device_info');

  /// 请求蓝牙扫描所需的全部权限
  static Future<bool> requestBlePermissions() async {
    if (!Platform.isAndroid) return true;

    final sdkInt = await _getAndroidSdkInt();
    final permissions = <Permission>[];

    if (sdkInt >= 31) {
      // Android 12+ 需要 BLUETOOTH_SCAN + BLUETOOTH_CONNECT
      permissions.addAll([
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
      ]);
      // Android 12-13 BLE 扫描仍需位置权限 (Android 14+ 不需要)
      if (sdkInt < 34) {
        permissions.add(Permission.locationWhenInUse);
      }
    } else {
      // Android 11 及以下需要位置权限 + 旧版蓝牙权限
      permissions.addAll([
        Permission.location,
        Permission.bluetooth,
      ]);
    }

    final statuses = await permissions.request();

    final allGranted = statuses.values.every(
      (status) => status.isGranted || status.isLimited,
    );

    if (!allGranted) {
      final denied = statuses.entries
          .where((e) => !e.value.isGranted && !e.value.isLimited)
          .map((e) => '${e.key}: ${e.value.name}')
          .join(', ');
      print('[BlePermissions] Denied: $denied');
    }

    return allGranted;
  }

  /// 检查蓝牙权限是否已授予
  static Future<bool> hasBlePermissions() async {
    if (!Platform.isAndroid) return true;

    final sdkInt = await _getAndroidSdkInt();

    if (sdkInt >= 31) {
      final btGranted = (await Permission.bluetoothScan.isGranted) &&
          (await Permission.bluetoothConnect.isGranted);
      // Android 12-13 还需要位置权限
      if (sdkInt < 34) {
        return btGranted && (await Permission.locationWhenInUse.isGranted);
      }
      return btGranted;
    } else {
      return (await Permission.location.isGranted) &&
          (await Permission.bluetooth.isGranted);
    }
  }

  /// 获取 Android SDK 版本号
  static Future<int> _getAndroidSdkInt() async {
    if (!Platform.isAndroid) return 0;
    try {
      final sdkInt = await _platform.invokeMethod<int>('getSdkInt');
      if (sdkInt != null) return sdkInt;
    } catch (_) {}
    // fallback: 假设 Android 12+，至少请求 bluetoothScan/connect
    return 31;
  }
}
