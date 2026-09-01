package com.doommeeting.server.controller;

import com.doommeeting.server.common.ApiResponse;
import com.doommeeting.server.dto.ChatDtos.ChatMessageResponse;
import com.doommeeting.server.dto.ChatDtos.MobileChatRequest;
import com.doommeeting.server.dto.MobileDtos.*;
import com.doommeeting.server.service.ChatService;
import com.doommeeting.server.service.LikeService;
import com.doommeeting.server.service.MemberService;
import com.doommeeting.server.service.RoomService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.*;

import java.util.List;
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
    private final ChatService chatService;

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

    /** 发送文字聊天消息(实时广播到房间内所有端) */
    @PostMapping("/{roomCode}/chat")
    public ApiResponse<ChatMessageResponse> sendChat(@PathVariable String roomCode,
                                                     @Valid @RequestBody MobileChatRequest request) {
        return ApiResponse.ok(chatService.sendFromMember(
                roomCode, request.identity(), request.memberToken(), request.content()));
    }

    /** 近期聊天记录(时间正序) */
    @GetMapping("/{roomCode}/chat")
    public ApiResponse<List<ChatMessageResponse>> chatHistory(@PathVariable String roomCode) {
        return ApiResponse.ok(chatService.recent(roomCode));
    }

    /** 播放控制: 手机端控制统一推流的播放/暂停/进度(转发 PC 端执行) */
    @PostMapping("/{roomCode}/cast/control")
    public ApiResponse<Void> castControl(@PathVariable String roomCode,
                                         @Valid @RequestBody CastControlRequest request) {
        memberService.castControl(roomCode, request);
        return ApiResponse.ok();
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
