package com.doommeeting.server.controller;

import com.doommeeting.server.common.ApiResponse;
import com.doommeeting.server.dto.ContentDtos.ContentResponse;
import com.doommeeting.server.dto.MobileDtos.*;
import com.doommeeting.server.entity.Room;
import com.doommeeting.server.entity.RoomMember;
import com.doommeeting.server.service.ContentService;
import com.doommeeting.server.service.LikeService;
import com.doommeeting.server.service.MemberService;
import com.doommeeting.server.service.PlaybackService;
import com.doommeeting.server.service.RoomService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

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
    private final ContentService contentService;

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

    /** 手机端上传真实文件并直接投放到本房间(会议结束后自动删除); 已有投放时需 replace=true 确认替换 */
    @PostMapping("/{roomCode}/contents/upload")
    public ApiResponse<ContentResponse> uploadAndCast(@PathVariable String roomCode,
                                                      @RequestParam("file") MultipartFile file,
                                                      @RequestParam String identity,
                                                      @RequestParam(required = false) String nickname,
                                                      @RequestParam(defaultValue = "false") boolean replace) {
        Room room = roomService.getRoomByCode(roomCode);
        // 与播放控制一致: 必须是房间在线成员, 操作人昵称以库中记录为准
        RoomMember member = memberService.requireOnlineMember(room, identity);
        String operator = member.getNickname();
        roomService.checkCastConflict(room.getId(), replace);
        ContentResponse content = contentService.upload(file, room.getId(), operator);
        try {
            roomService.castContent(room.getId(), content.id(), operator, replace);
        } catch (RuntimeException e) {
            // 投放失败时清理刚上传的文件与记录, 避免孤儿文件
            contentService.delete(content.id());
            throw e;
        }
        return ApiResponse.ok(content);
    }

    /** 房间实时状态(会议时间/剩余时长/播放状态/功能开关) */
    @GetMapping("/{roomCode}/state")
    public ApiResponse<Map<String, Object>> state(@PathVariable String roomCode) {
        return ApiResponse.ok(roomService.mobileState(roomCode));
    }
}
