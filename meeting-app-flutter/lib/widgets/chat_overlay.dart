import 'package:flutter/material.dart';

/// 聊天消息(内存展示)
class ChatMessageItem {
  final int id;
  final String sender;
  final String content;
  final bool fromAdmin;

  const ChatMessageItem({
    required this.id,
    required this.sender,
    required this.content,
    required this.fromAdmin,
  });
}

/// 左下角聊天气泡层: 最多显示 6 条, 新消息从下往上滑入
class ChatOverlay extends StatelessWidget {
  static const int maxVisible = 6;

  final List<ChatMessageItem> messages;

  const ChatOverlay({super.key, required this.messages});

  @override
  Widget build(BuildContext context) {
    final visible = messages.length <= maxVisible
        ? messages
        : messages.sublist(messages.length - maxVisible);
    return IgnorePointer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final message in visible)
            _ChatBubble(key: ValueKey(message.id), message: message),
        ],
      ),
    );
  }
}

class _ChatBubble extends StatefulWidget {
  final ChatMessageItem message;

  const _ChatBubble({super.key, required this.message});

  @override
  State<_ChatBubble> createState() => _ChatBubbleState();
}

class _ChatBubbleState extends State<_ChatBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    return SlideTransition(
      position: Tween<Offset>(begin: const Offset(0, 0.6), end: Offset.zero)
          .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut)),
      child: FadeTransition(
        opacity: _controller,
        child: Container(
          margin: const EdgeInsets.only(top: 4),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '${message.sender}: ',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: message.fromAdmin
                        ? const Color(0xFFFFC46B)
                        : const Color(0xFF8AB8FF),
                  ),
                ),
                TextSpan(
                  text: message.content,
                  style: const TextStyle(fontSize: 12, color: Colors.white),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
