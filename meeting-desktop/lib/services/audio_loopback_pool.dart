import 'package:livekit_client/livekit_client.dart' as lk;

/// 单条系统伴音回环采集通道
class LoopbackChannel {
  final lk.MediaDevice device;

  /// 配对播放端(输入端)的匹配关键字; null 表示采集系统默认输出
  /// (立体声混音类), 无需路由
  final List<String>? routeKeywords;

  LoopbackChannel(this.device, this.routeKeywords);

  /// 独占通道(虚拟声卡): 只采到定向路由进来的声音, 可按房间隔离
  bool get dedicated => routeKeywords != null;
}

/// 多房并发的回环采集通道分配器:
///
/// 本地视频推流时每个房间独占一条虚拟声卡通道(VB-CABLE / CABLE-A /
/// CABLE-B, 或开源 Virtual Cables 的 Virtual Cable 01..32),
/// 播放进程把声音定向路由进该通道, 各房间伴音互不串音;
/// 无空闲虚拟声卡时回退共享的立体声混音(采集默认输出, 多房间同时
/// 推流会串音, 由调用方提示操作员加装 CABLE A/B)。
class AudioLoopbackPool {
  AudioLoopbackPool._();

  static final AudioLoopbackPool instance = AudioLoopbackPool._();

  /// roomId -> 已占用的采集设备 deviceId
  final Map<int, String> _allocated = {};

  static const _sharedKeywords = [
    '立体声混音',
    '立體聲混音',
    'stereo mix',
    'what u hear',
    'what you hear',
    'wave out',
    'loopback',
  ];

  Future<List<LoopbackChannel>> _channels() async {
    final inputs = await lk.Hardware.instance.audioInputs();
    final channels = <LoopbackChannel>[];
    final virtualCablePattern = RegExp(r'virtual cable[\s-]*\d+');
    for (final device in inputs) {
      final label = device.label.toLowerCase();
      final virtualCable = virtualCablePattern.firstMatch(label);
      if (virtualCable != null) {
        // 开源 Virtual Cables: 同名的 "Virtual Cable NN" 播放/录音端点对
        channels.add(LoopbackChannel(device, [virtualCable.group(0)!]));
      } else if (label.contains('cable') && label.contains('output')) {
        // "CABLE Output (VB-Audio ...)"/"CABLE-A Output (...)" 的配对
        // 播放端为 "CABLE Input"/"CABLE-A Input"
        final pair =
            label.split('(').first.replaceFirst('output', 'input').trim();
        channels.add(LoopbackChannel(device, [pair]));
      } else if (label.contains('voicemeeter out')) {
        channels.add(LoopbackChannel(
            device, const ['voicemeeter input', 'voicemeeter aux input']));
      } else if (_sharedKeywords.any(label.contains)) {
        channels.add(LoopbackChannel(device, null));
      } else if (label.contains('virtual audio')) {
        channels.add(LoopbackChannel(device, [label.split('(').first.trim()]));
      }
    }
    return channels;
  }

  /// 为房间分配采集通道并登记占用。preferDedicated(本地视频推流)优先
  /// 空闲虚拟声卡; 屏幕推流优先立体声混音(采集默认输出)。
  /// 返回 null 表示没有任何可用回环设备
  Future<LoopbackChannel?> acquire(int roomId,
      {required bool preferDedicated}) async {
    release(roomId);
    List<LoopbackChannel> channels;
    try {
      channels = await _channels();
    } catch (_) {
      return null;
    }
    final busy = _allocated.values.toSet();
    final freeDedicated = channels
        .where((c) => c.dedicated && !busy.contains(c.device.deviceId))
        .toList();
    final shared = channels.where((c) => !c.dedicated).toList();
    final ordered = preferDedicated
        ? [...freeDedicated, ...shared]
        : [...shared, ...freeDedicated];
    if (ordered.isEmpty) return null;
    final chosen = ordered.first;
    _allocated[roomId] = chosen.device.deviceId;
    return chosen;
  }

  /// 该设备是否也被其他房间占用(共享设备多房间同时采集会串音)
  bool sharedWithOtherRooms(int roomId, String deviceId) => _allocated.entries
      .any((entry) => entry.key != roomId && entry.value == deviceId);

  void release(int roomId) => _allocated.remove(roomId);
}
