package com.doommeeting.server.controller;

import com.doommeeting.server.common.ApiResponse;
import com.doommeeting.server.dto.MobileDtos.*;
import com.doommeeting.server.service.LikeService;
import com.doommeeting.server.service.MemberService;
import com.doommeeting.server.service.RoomService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

/**
 * 手机客户端接口: 扫码入会/离会/心跳/点赞/录屏上报/房间状态
 */
@RestController
@RequestMapping("/api/mobile/rooms")
@RequiredArgsConstructor
public class MobileRoomController {

    private final MemberService memberService;
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
        memberService.leave(roomCode, request.identity(), request.memberToken());
        return ApiResponse.ok();
    }

    @PostMapping("/{roomCode}/heartbeat")
    public ApiResponse<Void> heartbeat(@PathVariable String roomCode,
                                       @Valid @RequestBody HeartbeatRequest request) {
        memberService.heartbeat(roomCode, request.identity(), request.memberToken());
        return ApiResponse.ok();
    }

    /** 点赞: 实时连接到 PC 端并记录 */
    @PostMapping("/{roomCode}/like")
    public ApiResponse<Map<String, Object>> like(@PathVariable String roomCode,
                                                 @Valid @RequestBody LikeRequest request) {
        long likeCount = likeService.like(roomCode, request.identity(), request.memberToken());
        return ApiResponse.ok(Map.of("likeCount", likeCount));
    }

    /** 录屏检测上报(允许截屏, 禁止录制) */
    @PostMapping("/{roomCode}/report-recording")
    public ApiResponse<Void> reportRecording(@PathVariable String roomCode,
                                             @Valid @RequestBody RecordingReportRequest request) {
        memberService.reportRecording(roomCode, request);
        return ApiResponse.ok();
    }

    /** 房间实时状态(会议时间/剩余时长/推流状态/功能开关) */
    @GetMapping("/{roomCode}/state")
    public ApiResponse<Map<String, Object>> state(@PathVariable String roomCode) {
        return ApiResponse.ok(roomService.mobileState(roomCode));
    }
}
