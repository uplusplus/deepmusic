import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'features/settings/services/app_settings.dart';
import 'features/practice/services/volume_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 加载用户设置
  await AppSettings().load();

  // 初始化音量服务
  await VolumeService().init();

  // 允许横屏和竖屏，不锁定方向
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // 全屏沉浸式 (练习页更沉浸)
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  runApp(
    const ProviderScope(
      child: DeepMusicApp(),
    ),
  );
}
