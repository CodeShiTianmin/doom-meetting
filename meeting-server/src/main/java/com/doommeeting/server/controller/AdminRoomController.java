package com.doommeeting.server.controller;

import com.doommeeting.server.common.ApiResponse;
import com.doommeeting.server.dto.LikeDtos.LikeRecordResponse;
import com.doommeeting.server.dto.RoomDtos.*;
import com.doommeeting.server.dto.MobileDtos.ChatMessageResponse;
import com.doommeeting.server.service.ChatService;
import com.doommeeting.server.service.LikeService;
import com.doommeeting.server.service.LiveKitTokenService;
import com.doommeeting.server.service.MemberManagementService;
import com.doommeeting.server.service.PlaybackService;
import com.doommeeting.server.service.RoomService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;

/**
 * PC 管理端房间接口: 创建/列表/详情/设置/投放/关闭/成员/点赞/事件
 */
@RestController
@RequestMapping("/api/admin/rooms")
@RequiredArgsConstructor
public class AdminRoomController {

    private final RoomService roomService;
    private final LikeService likeService;
    private final LiveKitTokenService liveKitTokenService;
    private final PlaybackService playbackService;
    private final MemberManagementService memberManagementService;
    private final ChatService chatService;

    /** 踢出成员(同时从 LiveKit 服务端断开其媒体连接) */
    @PostMapping("/{id}/members/{identity}/kick")
    public ApiResponse<Void> kickMember(@PathVariable Long id, @PathVariable String identity,
                                        Authentication authentication) {
        memberManagementService.kick(id, identity, authentication.getName());
        return ApiResponse.ok();
    }

    /** 单人静音/取消静音 */
    @PostMapping("/{id}/members/{identity}/mute")
    public ApiResponse<Void> muteMember(@PathVariable Long id, @PathVariable String identity,
                                        @RequestParam(defaultValue = "true") boolean muted,
                                        Authentication authentication) {
        memberManagementService.mute(id, identity, muted, authentication.getName());
        return ApiResponse.ok();
    }

    /** 全员静音/解除全员静音 */
    @PostMapping("/{id}/members/mute-all")
    public ApiResponse<Void> muteAll(@PathVariable Long id,
                                     @RequestParam(defaultValue = "true") boolean muted,
                                     Authentication authentication) {
        memberManagementService.muteAll(id, muted, authentication.getName());
        return ApiResponse.ok();
    }

    /** 禁止/允许成员开启摄像头 */
    @PostMapping("/{id}/members/{identity}/camera")
    public ApiResponse<Void> setMemberCamera(@PathVariable Long id, @PathVariable String identity,
                                             @RequestParam(defaultValue = "true") boolean disabled,
                                             Authentication authentication) {
        memberManagementService.setCameraDisabled(id, identity, disabled, authentication.getName());
        return ApiResponse.ok();
    }

    /** 等候室审批: 批准/拒绝入会申请 */
    @PostMapping("/{id}/members/{identity}/approve")
    public ApiResponse<Void> approveMember(@PathVariable Long id, @PathVariable String identity,
                                           @RequestParam(defaultValue = "true") boolean approved,
                                           Authentication authentication) {
        memberManagementService.approve(id, identity, approved, authentication.getName());
        return ApiResponse.ok();
    }

    /** 会后出席统计报表(出席时长/离会次数/点赞数) */
    @GetMapping("/{id}/attendance")
    public ApiResponse<List<AttendanceResponse>> attendance(@PathVariable Long id) {
        return ApiResponse.ok(roomService.attendance(id));
    }

    /** 主持人发送聊天消息 */
    @PostMapping("/{id}/chat")
    public ApiResponse<ChatMessageResponse> sendChat(@PathVariable Long id,
                                                     @Valid @RequestBody AdminChatRequest request,
                                                     Authentication authentication) {
        return ApiResponse.ok(chatService.sendAsAdmin(id, authentication.getName(), request.content()));
    }

    /** 聊天历史(最近 100 条) */
    @GetMapping("/{id}/chat")
    public ApiResponse<List<ChatMessageResponse>> chatHistory(@PathVariable Long id) {
        return ApiResponse.ok(chatService.historyByRoomId(id));
    }

    @PostMapping
    public ApiResponse<RoomResponse> createRoom(@Valid @RequestBody CreateRoomRequest request,
                                                Authentication authentication) {
        return ApiResponse.ok(roomService.createRoom(request, authentication.getName()));
    }

    @GetMapping
    public ApiResponse<List<RoomResponse>> listRooms(@RequestParam(required = false) String status) {
        return ApiResponse.ok(roomService.listRooms(status));
    }

    @GetMapping("/{id}")
    public ApiResponse<RoomResponse> getRoom(@PathVariable Long id) {
        return ApiResponse.ok(roomService.getRoom(id));
    }

    @PutMapping("/{id}/settings")
    public ApiResponse<RoomResponse> updateSettings(@PathVariable Long id,
                                                    @Valid @RequestBody RoomSettingsRequest request) {
        return ApiResponse.ok(roomService.updateSettings(id, request));
    }

    @PostMapping("/{id}/cast")
    public ApiResponse<RoomResponse> castContent(@PathVariable Long id,
                                                 @Valid @RequestBody CastRequest request,
                                                 Authentication authentication) {
        return ApiResponse.ok(roomService.castContent(id, request.contentId(),
                authentication.getName(), Boolean.TRUE.equals(request.replace())));
    }

    /** PC 端屏幕/窗口共享开始登记(跨端冲突检查可感知) */
    @PostMapping("/{id}/screen-share/start")
    public ApiResponse<RoomResponse> startScreenShare(@PathVariable Long id,
                                                      @RequestParam(defaultValue = "false") boolean replace,
                                                      Authentication authentication) {
        return ApiResponse.ok(roomService.startScreenShare(id, authentication.getName(), replace));
    }

    /** PC 端屏幕/窗口共享停止登记 */
    @PostMapping("/{id}/screen-share/stop")
    public ApiResponse<RoomResponse> stopScreenShare(@PathVariable Long id,
                                                     Authentication authentication) {
        return ApiResponse.ok(roomService.stopScreenShare(id, authentication.getName()));
    }

    /** 停止当前投放: 清除房间当前内容并重置播放状态 */
    @PostMapping("/{id}/cast/stop")
    public ApiResponse<RoomResponse> stopCast(@PathVariable Long id,
                                              Authentication authentication) {
        return ApiResponse.ok(roomService.stopCast(id, authentication.getName()));
    }

    /** PC 端播放控制: 播放/暂停/拖动进度/明暗/音量, 实时下发到房间内全部手机端 */
    @PostMapping("/{id}/playback")
    public ApiResponse<Map<String, Object>> playback(@PathVariable Long id,
                                                     @Valid @RequestBody AdminPlaybackRequest request,
                                                     Authentication authentication) {
        return ApiResponse.ok(playbackService.adminControl(id, request, authentication.getName()));
    }

    @PostMapping("/{id}/close")
    public ApiResponse<Void> closeRoom(@PathVariable Long id) {
        roomService.closeRoom(id);
        return ApiResponse.ok();
    }

    @PostMapping("/{id}/invite/regenerate")
    public ApiResponse<RoomResponse> regenerateInvite(@PathVariable Long id) {
        return ApiResponse.ok(roomService.regenerateInvite(id));
    }

    /** PC 隐藏推流端入会 Token(只发不收, 不出现在成员列表) */
    @GetMapping("/{id}/publisher-token")
    public ApiResponse<Map<String, String>> publisherToken(@PathVariable Long id,
                                                           Authentication authentication) {
        var room = roomService.getRoom(id);
        String token = liveKitTokenService.createHiddenPublisherToken(
                room.roomCode(), "pc-publisher-" + authentication.getName() + "-" + id);
        return ApiResponse.ok(Map.of(
                "livekitToken", token,
                "livekitWsUrl", liveKitTokenService.getWsUrl(),
                "roomCode", room.roomCode()));
    }

    @GetMapping("/{id}/members")
    public ApiResponse<List<MemberResponse>> listMembers(@PathVariable Long id) {
        return ApiResponse.ok(roomService.listMembers(id));
    }

    @GetMapping("/{id}/likes")
    public ApiResponse<List<LikeRecordResponse>> listLikes(@PathVariable Long id) {
        return ApiResponse.ok(likeService.listByRoom(id));
    }

    @GetMapping("/{id}/events")
    public ApiResponse<List<RoomEventResponse>> listEvents(@PathVariable Long id) {
        return ApiResponse.ok(roomService.listEvents(id));
    }
}
