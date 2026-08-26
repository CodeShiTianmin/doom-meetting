import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'pages/login_page.dart';
import 'pages/player_window_page.dart';
import 'services/cast_manager.dart';

void main(List<String> args) {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  // 子窗口入口: 独立本地视频播放窗口(desktop_multi_window 以相同 main 启动子引擎)
  if (args.isNotEmpty && args.first == 'multi_window') {
    final windowId = int.parse(args[1]);
    final params = jsonDecode(args[2]) as Map<String, dynamic>;
    runApp(PlayerWindowApp(windowId: windowId, params: params));
    return;
  }
  CastManager.instance.bindPlayerWindowEvents();
  runApp(const MeetingDesktopApp());
}

class MeetingDesktopApp extends StatelessWidget {
  const MeetingDesktopApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '投屏会议 - PC 投屏端',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF5B8DEF),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF0A0E27),
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(12))),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: Colors.white10),
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0A0E27),
          surfaceTintColor: Colors.transparent,
        ),
      ),
      home: const LoginPage(),
    );
  }
}
