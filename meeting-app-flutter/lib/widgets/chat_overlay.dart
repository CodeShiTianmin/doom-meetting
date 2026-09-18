import 'package:flutter/material.dart';

import '../services/api_client.dart';

/// 聊天消息(内存展示)。[key] 为去重标识: 优先用服务端消息 id,
/// 兼容无 id 的旧服务端时退化为 发送者+内容+发送时间。
/// 图片消息 [imageUrl] 非空(已拼成绝对地址), 此时 [content] 为空。
class ChatMessageItem {
  final String key;
  final String sender;
  final String content;
  final String? imageUrl;
  final bool fromAdmin;

  const ChatMessageItem({
    required this.key,
    required this.sender,
    required this.content,
    this.imageUrl,
    required this.fromAdmin,
  });

  bool get isImage => imageUrl != null && imageUrl!.isNotEmpty;

  factory ChatMessageItem.fromJson(Map<String, dynamic> json) {
    final sender = (json['sender'] as String?) ?? '匿名';
    final content = (json['content'] as String?) ?? '';
    final rawImage = json['imageUrl'];
    final imageUrl = rawImage is String && rawImage.isNotEmpty
        ? ApiClient.resolveImageUrl(rawImage)
        : null;
    final id = json['id'];
    final key = id is String && id.isNotEmpty
        ? id
        : '${json['identity'] ?? ''}|$sender|${json['sentAt'] ?? ''}|'
            '${imageUrl ?? content}';
    return ChatMessageItem(
      key: key,
      sender: sender,
      content: content,
      imageUrl: imageUrl,
      fromAdmin: json['fromAdmin'] == true,
    );
  }
}

/// 左下角聊天气泡层: 最多显示 6 条, 新消息从下往上滑入。
/// 图片消息显示缩略图, 点击通过 [onImageTap] 打开大图; 文字气泡不拦截点击。
class ChatOverlay extends StatelessWidget {
  static const int maxVisible = 6;

  final List<ChatMessageItem> messages;
  final ValueChanged<ChatMessageItem>? onImageTap;

  const ChatOverlay({super.key, required this.messages, this.onImageTap});

  @override
  Widget build(BuildContext context) {
    final visible = messages.length <= maxVisible
        ? messages
        : messages.sublist(messages.length - maxVisible);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final message in visible)
          if (message.isImage)
            _ChatBubble(
              key: ValueKey(message.key),
              message: message,
              onTap: onImageTap == null ? null : () => onImageTap!(message),
            )
          else
            IgnorePointer(
              child: _ChatBubble(key: ValueKey(message.key), message: message),
            ),
      ],
    );
  }
}

/// 全屏查看聊天图片(双指缩放, 点击空白关闭)
class ChatImageViewer extends StatelessWidget {
  final ChatMessageItem message;

  const ChatImageViewer({super.key, required this.message});

  static Future<void> show(BuildContext context, ChatMessageItem message) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => ChatImageViewer(message: message),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).pop(),
      child: Stack(
        children: [
          Center(
            child: InteractiveViewer(
              minScale: 0.8,
              maxScale: 5,
              child: Image.network(
                message.imageUrl!,
                fit: BoxFit.contain,
                loadingBuilder: (context, child, progress) => progress == null
                    ? child
                    : const Center(
                        child: CircularProgressIndicator(color: Colors.white)),
                errorBuilder: (_, __, ___) => const Icon(Icons.broken_image,
                    size: 64, color: Colors.white54),
              ),
            ),
          ),
          Positioned(
            left: 16,
            bottom: 24,
            child: Text('${message.sender} 发送的图片',
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
          ),
          Positioned(
            top: 36,
            right: 12,
            child: IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatBubble extends StatefulWidget {
  final ChatMessageItem message;
  final VoidCallback? onTap;

  const _ChatBubble({super.key, required this.message, this.onTap});

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
    final senderStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      color:
          message.fromAdmin ? const Color(0xFFFFC46B) : const Color(0xFF8AB8FF),
    );
    final Widget body = message.isImage
        ? Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${message.sender}: [图片]', style: senderStyle),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: ConstrainedBox(
                  constraints:
                      const BoxConstraints(maxWidth: 160, maxHeight: 120),
                  child: Image.network(
                    message.imageUrl!,
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, progress) =>
                        progress == null
                            ? child
                            : const SizedBox(
                                width: 120,
                                height: 80,
                                child: Center(
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white70)),
                              ),
                    errorBuilder: (_, __, ___) => const SizedBox(
                      width: 120,
                      height: 80,
                      child: Center(
                          child: Icon(Icons.broken_image,
                              color: Colors.white54)),
                    ),
                  ),
                ),
              ),
            ],
          )
        : Text.rich(
            TextSpan(
              children: [
                TextSpan(text: '${message.sender}: ', style: senderStyle),
                TextSpan(
                  text: message.content,
                  style: const TextStyle(fontSize: 12, color: Colors.white),
                ),
              ],
            ),
          );
    return SlideTransition(
      position: Tween<Offset>(begin: const Offset(0, 0.6), end: Offset.zero)
          .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut)),
      child: FadeTransition(
        opacity: _controller,
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(12),
            ),
            child: body,
          ),
        ),
      ),
    );
  }
}
