import 'dart:math' as math;

import 'package:flutter/material.dart';

class HeartItem {
  final int id;
  final double left;

  HeartItem({required this.id, required this.left});

  static final math.Random _random = math.Random();

  factory HeartItem.random(int id) =>
      HeartItem(id: id, left: 0.72 + _random.nextDouble() * 0.2);
}

/// 点赞飘心动画层
class FloatingHearts extends StatelessWidget {
  final List<HeartItem> hearts;

  const FloatingHearts({super.key, required this.hearts});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return IgnorePointer(
      child: Stack(
        children: [
          for (final heart in hearts)
            _FloatingHeart(
              key: ValueKey(heart.id),
              left: heart.left * size.width,
              bottom: 140,
            ),
        ],
      ),
    );
  }
}

class _FloatingHeart extends StatefulWidget {
  final double left;
  final double bottom;

  const _FloatingHeart({super.key, required this.left, required this.bottom});

  @override
  State<_FloatingHeart> createState() => _FloatingHeartState();
}

class _FloatingHeartState extends State<_FloatingHeart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        return Positioned(
          left: widget.left,
          bottom: widget.bottom + t * 220,
          child: Opacity(
            opacity: (1 - t).clamp(0.0, 0.9),
            child: Transform.scale(
              scale: 0.6 + t * 0.65,
              child: const Icon(Icons.favorite, color: Colors.pinkAccent, size: 28),
            ),
          ),
        );
      },
    );
  }
}
