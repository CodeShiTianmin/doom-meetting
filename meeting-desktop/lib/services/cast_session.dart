import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import 'package:livekit_client/livekit_client.dart' as lk;

/// 单房间推流会话:
///
/// 每个房间一个独立的 LiveKit RTC 连接(隐藏推流身份, 只发不收)。
/// 统一推流模式下, 全部房间会话对同一个共享播放窗口做窗口捕获,
/// 只解码播放一路视频, 各房间发布各自的捕获轨。
///
/// 捕获窗口时伴音按进程隔离采集(WASAPI, Win10 2004+):
/// 只采共享播放进程的声音, 不混入系统其它声音。
class CastSession extends ChangeNotifier {
  final int roomId;
  final String roomCode;

  CastSession({required this.roomId, required this.roomCode});

  lk.Room? _lkRoom;

  /// 当前推流源名称(视频文件名)
  String? sourceLabel;
  String? error;
  bool connected = false;
  bool publishing = false;

  /// 当前发布的视频轨, 供单房页面内嵌预览
  lk.LocalVideoTrack? localVideoTrack;

  /// 系统伴音采集失败时的提示(推流仅有画面无声音)
  String? audioCaptureWarning;

  /// 连接 LiveKit(隐藏推流身份)
  Future<void> connect(String wsUrl, String token) async {
    if (connected) return;
    final room = lk.Room(
      roomOptions: const lk.RoomOptions(
        adaptiveStream: false,
        dynacast: true,
        defaultVideoPublishOptions: lk.VideoPublishOptions(
          // 高清 1080p/30fps; 1080p30 屏幕/视频内容 4Mbps 已接近主观清晰度
          // 上限, 码率再高只会挤占手机下行带宽造成卡顿
          videoEncoding: lk.VideoEncoding(
            maxBitrate: 4 * 1000 * 1000,
            maxFramerate: 30,
          ),
          simulcast: true,
          // H264 走硬件编码: 多房并发时大幅降低 CPU/GPU 占用,
          // 避免软编 VP8 算力不足时出现条纹/色块等编码伪影
          videoCodec: 'H264',
        ),
        defaultScreenShareCaptureOptions: lk.ScreenShareCaptureOptions(
          maxFrameRate: 30,
          params: lk.VideoParameters(
            dimensions: lk.VideoDimensionsPresets.h1080_169,
            encoding: lk.VideoEncoding(
              maxBitrate: 4 * 1000 * 1000,
              maxFramerate: 30,
            ),
          ),
        ),
      ),
    );
    await room.connect(wsUrl, token);
    _lkRoom = room;
    connected = true;
    notifyListeners();
  }

  /// 统一推流: 捕获共享播放窗口并发布到本房间
  Future<void> startWindowCast(webrtc.DesktopCapturerSource source,
      {String? label}) async {
    await stopCast();
    final participant = _requireParticipant();
    final hasCaptureAudio = await _publishCaptureTrack(participant, source.id);
    if (!hasCaptureAudio) {
      audioCaptureWarning = '本房间伴音采集失败, 推流仅有画面无声音';
    }
    sourceLabel = label ?? source.name;
    publishing = true;
    notifyListeners();
  }

  /// 创建并发布窗口捕获轨。Windows 上随画面同时用 WASAPI 回环采集
  /// 伴音: 捕获窗口时只采该窗口所属进程的声音(按进程隔离, 需 Win10
  /// 2004+)。返回是否成功发布了伴音轨。发布失败时停止轨道避免泄漏捕获会话
  Future<bool> _publishCaptureTrack(
      lk.LocalParticipant participant, String sourceId) async {
    final options = lk.ScreenShareCaptureOptions(
      sourceId: sourceId,
      maxFrameRate: 30,
      params: const lk.VideoParameters(
        dimensions: lk.VideoDimensionsPresets.h1080_169,
        encoding: lk.VideoEncoding(
          maxBitrate: 4 * 1000 * 1000,
          maxFramerate: 30,
        ),
      ),
    );
    lk.LocalVideoTrack videoTrack;
    lk.LocalAudioTrack? audioTrack;
    try {
      final tracks =
          await lk.LocalVideoTrack.createScreenShareTracksWithAudio(options);
      videoTrack = tracks.whereType<lk.LocalVideoTrack>().first;
      audioTrack = tracks.whereType<lk.LocalAudioTrack>().firstOrNull;
    } catch (_) {
      videoTrack = await lk.LocalVideoTrack.createScreenShareTrack(options);
    }
    localVideoTrack = videoTrack;
    try {
      // 顶层 1080p30/4Mbps 独立满码率编码, 另发 720p/360p 全帧率低档层:
      // 手机下行带宽不足时 SFU 自动切低档层保持流畅, 带宽充足时始终收
      // 顶层高清; 低档层保持 30fps 避免视频内容切档后掉帧卡顿。
      // 发送端带宽/性能不足时优先保帧率(降分辨率), 避免卡顿
      await participant.publishVideoTrack(
        videoTrack,
        publishOptions: const lk.VideoPublishOptions(
          simulcast: true,
          videoCodec: 'H264',
          videoEncoding: lk.VideoEncoding(
            maxBitrate: 4 * 1000 * 1000,
            maxFramerate: 30,
          ),
          screenShareSimulcastLayers: [
            lk.VideoParameters(
              dimensions: lk.VideoDimensionsPresets.h360_169,
              encoding: lk.VideoEncoding(
                maxBitrate: 800 * 1000,
                maxFramerate: 30,
              ),
            ),
            lk.VideoParameters(
              dimensions: lk.VideoDimensionsPresets.h720_169,
              encoding: lk.VideoEncoding(
                maxBitrate: 2200 * 1000,
                maxFramerate: 30,
              ),
            ),
          ],
          // 保分辨率: 编码器算力/带宽吃紧时降帧率而非动态缩放分辨率,
          // 非整数比例缩放屏幕/视频内容会产生横向条纹状锟齿波纹
          degradationPreference: lk.DegradationPreference.maintainResolution,
        ),
      );
    } catch (error) {
      await videoTrack.stop();
      await audioTrack?.stop();
      rethrow;
    }
    if (audioTrack == null) return false;
    try {
      await participant.publishAudioTrack(audioTrack);
      return true;
    } catch (_) {
      await audioTrack.stop();
      return false;
    }
  }

  /// 未连接时直接报错, 避免静默跳过推流却显示投屏中的"假成功"
  lk.LocalParticipant _requireParticipant() {
    final participant = connected ? _lkRoom?.localParticipant : null;
    if (participant == null) {
      throw StateError('媒体服务未连接, 无法推流');
    }
    return participant;
  }

  /// 停止推流: 任一环节失败/超时不阻塞后续清理, 保证本地状态一定复位
  Future<void> stopCast() async {
    final participant = _lkRoom?.localParticipant;
    if (participant != null) {
      for (final publication in participant.trackPublications.values.toList()) {
        final track = publication.track;
        try {
          await participant
              .removePublishedTrack(publication.sid)
              .timeout(const Duration(seconds: 5));
        } catch (_) {}
        // 确保底层采集会话一定停止: 否则取消推流后窗口捕获
        // 仍在后台运行, 多房并发时持续占用显卡与 CPU
        try {
          await track?.stop();
        } catch (_) {}
      }
    }
    localVideoTrack = null;
    sourceLabel = null;
    audioCaptureWarning = null;
    publishing = false;
    notifyListeners();
  }

  Future<void> disconnect() async {
    await stopCast();
    await _lkRoom?.disconnect();
    await _lkRoom?.dispose();
    _lkRoom = null;
    connected = false;
    notifyListeners();
  }
}
