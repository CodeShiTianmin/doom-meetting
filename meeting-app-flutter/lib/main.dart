import 'package:flutter/material.dart';

import 'pages/join_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MeetingApp());
}

class MeetingApp extends StatelessWidget {
  const MeetingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '投屏会议',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF5B8DEF),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF05071C),
      ),
      home: const JoinPage(),
    );
  }
}
