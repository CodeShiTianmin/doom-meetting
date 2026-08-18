import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 全屏防录制水印: 客户身份 + 实时时间, 斜向平铺, 低透明度
class Watermark extends StatefulWidget {
  final String identityText;

  const Watermark({super.key, required this.identityText});

  @override
  State<Watermark> createState() => _WatermarkState();
}

class _WatermarkState extends State<Watermark> {
  late Timer _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  String get _text {
    final t =
        '${_now.year}-${_now.month.toString().padLeft(2, '0')}-${_now.day.toString().padLeft(2, '0')} '
        '${_now.hour.toString().padLeft(2, '0')}:${_now.minute.toString().padLeft(2, '0')}';
    return '${widget.identityText}  $t';
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              for (int row = 0; row < 4; row++)
                for (int col = 0; col < 3; col++)
                  Positioned(
                    left: col * constraints.maxWidth / 3,
                    top: row * constraints.maxHeight / 4 + (col.isOdd ? 40 : 0),
                    child: Transform.rotate(
                      angle: -math.pi / 9,
                      child: Text(
                        _text,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.white.withOpacity(0.07),
                        ),
                      ),
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}
