package com.doommeeting.server.controller;

import com.doommeeting.server.common.ApiResponse;
import com.doommeeting.server.dto.MobileDtos.*;
import com.doommeeting.server.entity.ContentItem;
import com.doommeeting.server.entity.Room;
import com.doommeeting.server.enums.RoomStatus;
import com.doommeeting.server.service.LikeService;
import com.doommeeting.server.service.MemberService;
import com.doommeeting.server.service.PlaybackService;
import com.doommeeting.server.service.RoomService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.*;

import java.time.Duration;
import java.time.LocalDateTime;
import java.util.HashMap;
import java.util.Map;

/**
 * 手机客户端接口: 扫码入会/离会/心跳/播放控制/点赞/录屏上报/房间状态
 */
@RestController
@RequestMapping("/api/mobile/rooms")
@RequiredArgsConstructor
public class MobileRoomController {

    private final MemberService memberService;
    private final PlaybackService playbackService;
    private final LikeService likeService;
    private final RoomService roomService;

    /** 扫码入会: 校验一次性凭证 -> 签发 LiveKit 入会 JWT */
    @PostMapping("/join")
    public ApiResponse<JoinRoomResponse> join(@Valid @RequestBody JoinRoomRequest request) {
        return ApiResponse.ok(memberService.join(request));
    }

    @PostMapping("/{roomCode}/leave")
    public ApiResponse<Void> leave(@PathVariable String roomCode,
                                   @Valid @RequestBody LeaveRequest request) {
        memberService.leave(roomCode, request.identity());
        return ApiResponse.ok();
    }

    @PostMapping("/{roomCode}/heartbeat")
    public ApiResponse<Void> heartbeat(@PathVariable String roomCode,
                                       @Valid @RequestBody HeartbeatRequest request) {
        memberService.heartbeat(roomCode, request.identity());
        return ApiResponse.ok();
    }

    /** 播放控制: 开始播放/暂停/拖拉进度条/调节明暗/调节声音 */
    @PostMapping("/{roomCode}/playback")
    public ApiResponse<Map<String, Object>> playback(@PathVariable String roomCode,
                                                     @Valid @RequestBody PlaybackControlRequest request) {
        return ApiResponse.ok(playbackService.control(roomCode, request));
    }

    /** 点赞: 实时连接到 PC 端并记录 */
    @PostMapping("/{roomCode}/like")
    public ApiResponse<Map<String, Object>> like(@PathVariable String roomCode,
                                                 @Valid @RequestBody LikeRequest request) {
        long likeCount = likeService.like(roomCode, request.identity());
        return ApiResponse.ok(Map.of("likeCount", likeCount));
    }

    /** 录屏检测上报(允许截屏, 禁止录制) */
    @PostMapping("/{roomCode}/report-recording")
    public ApiResponse<Void> reportRecording(@PathVariable String roomCode,
                                             @Valid @RequestBody RecordingReportRequest request) {
        memberService.reportRecording(roomCode, request);
        return ApiResponse.ok();
    }

    /** 房间实时状态(会议时间/剩余时长/播放状态/功能开关) */
    @GetMapping("/{roomCode}/state")
    public ApiResponse<Map<String, Object>> state(@PathVariable String roomCode) {
        Room room = roomService.getRoomByCode(roomCode);
        Map<String, Object> state = new HashMap<>();
        state.put("roomCode", room.getRoomCode());
        state.put("name", room.getName());
        state.put("status", room.getStatus().name());
        state.put("videoCallEnabled", room.getVideoCallEnabled());
        state.put("cameraEnabled", room.getCameraEnabled());
        state.put("screenshotAllowed", room.getScreenshotAllowed());
        state.put("recordingForbidden", room.getRecordingForbidden());
        state.put("durationMinutes", room.getDurationMinutes());
        state.put("meetingStartAt", room.getMeetingStartAt());
        state.put("meetingEndAt", room.getMeetingEndAt());
        if (room.getStatus() == RoomStatus.RUNNING && room.getMeetingEndAt() != null) {
            state.put("remainingSeconds", Math.max(0,
                    Duration.between(LocalDateTime.now(), room.getMeetingEndAt()).getSeconds()));
        }
        state.put("playbackState", room.getPlaybackState().name());
        state.put("playbackPositionSeconds", room.getPlaybackPositionSeconds());
        state.put("likeCount", room.getLikeCount());
        ContentItem content = room.getCurrentContent();
        state.put("contentId", content == null ? null : content.getId());
        state.put("contentName", content == null ? null : content.getName());
        state.put("contentDurationSeconds", content == null ? null : content.getDurationSeconds());
        return ApiResponse.ok(state);
    }
}
