import 'dart:io';
import 'package:permission_handler/permission_handler.dart';

/// Android 12+ (API 31+) 蓝牙权限工具
class BlePermissions {
  /// 请求蓝牙扫描所需的全部权限
  static Future<bool> requestBlePermissions() async {
    if (!Platform.isAndroid) return true;

    final permissions = <Permission>[];

    // Android 12+ (API 31+)
    if (await _getAndroidSdkInt() >= 31) {
      permissions.addAll([
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
      ]);
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
          .map((e) => e.key.toString())
          .join(', ');
      print('[BlePermissions] Denied: $denied');
    }

    return allGranted;
  }

  /// 检查蓝牙权限是否已授予
  static Future<bool> hasBlePermissions() async {
    if (!Platform.isAndroid) return true;

    if (await _getAndroidSdkInt() >= 31) {
      return (await Permission.bluetoothScan.isGranted) &&
          (await Permission.bluetoothConnect.isGranted);
    } else {
      return (await Permission.location.isGranted) &&
          (await Permission.bluetooth.isGranted);
    }
  }

  static Future<int> _getAndroidSdkInt() async {
    // Android 12 = SDK 31, Android 13 = SDK 33, Android 14 = SDK 34
    // 简单方式: 通过 permission_handler 的行为推断
    // 或者通过 platform channel 获取，这里用一个保守的默认值
    try {
      // permission_handler 没有直接获取 SDK 版本的 API
      // 我们通过检查 bluetoothScan 权限状态来间接判断
      final scanStatus = await Permission.bluetoothScan.status;
      // 如果 bluetoothScan 权限存在（Android 12+），返回 31
      // 如果返回 denied/permanentlyDenied 也说明是 Android 12+
      if (scanStatus != PermissionStatus.permanentlyDenied) {
        return 31; // 假设 Android 12+
      }
    } catch (_) {}
    return 30; // Android 11 及以下
  }
}
