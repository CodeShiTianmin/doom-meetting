package com.doommeeting.server.controller;

import com.doommeeting.server.common.ApiResponse;
import com.doommeeting.server.dto.ChatDtos.AdminChatRequest;
import com.doommeeting.server.dto.ChatDtos.ChatMessageResponse;
import com.doommeeting.server.dto.LikeDtos.LikeRecordResponse;
import com.doommeeting.server.dto.RoomDtos.*;
import com.doommeeting.server.service.ChatService;
import com.doommeeting.server.service.LikeService;
import com.doommeeting.server.service.LiveKitTokenService;
import com.doommeeting.server.service.MemberManagementService;
import com.doommeeting.server.service.RoomService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;

/**
 * PC 管理端房间接口: 创建/列表/详情/设置/推流登记/关闭/成员/点赞/事件
 */
@RestController
@RequestMapping("/api/admin/rooms")
@RequiredArgsConstructor
public class AdminRoomController {

    private final RoomService roomService;
    private final LikeService likeService;
    private final ChatService chatService;
    private final LiveKitTokenService liveKitTokenService;
    private final MemberManagementService memberManagementService;

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

    /** PC 端开始推流登记(屏幕/本地视频/摄像头, 均走 LiveKit 实时流) */
    @PostMapping("/{id}/cast/start")
    public ApiResponse<RoomResponse> startCast(@PathVariable Long id,
                                               @Valid @RequestBody CastStartRequest request,
                                               Authentication authentication) {
        return ApiResponse.ok(roomService.startCast(id, request.type(), request.label(),
                authentication.getName(), Boolean.TRUE.equals(request.replace())));
    }

    /** 停止当前推流 */
    @PostMapping("/{id}/cast/stop")
    public ApiResponse<RoomResponse> stopCast(@PathVariable Long id,
                                              Authentication authentication) {
        return ApiResponse.ok(roomService.stopCast(id, authentication.getName()));
    }

    /** 单房播放状态广播: PC 端该房间播放器状态同步到该房间的手机端 */
    @PostMapping("/{id}/cast/playback")
    public ApiResponse<Void> broadcastPlayback(@PathVariable Long id,
                                               @Valid @RequestBody PlaybackStateRequest request) {
        roomService.broadcastPlayback(id, request.playing(), request.positionMs(), request.durationMs());
        return ApiResponse.ok();
    }

    /** 手动结束会议并重置固定房间(旧凭证失效, 签发新客户码/服务码) */
    @PostMapping("/{id}/reset")
    public ApiResponse<RoomResponse> resetRoom(@PathVariable Long id,
                                               Authentication authentication) {
        return ApiResponse.ok(roomService.resetRoom(id, authentication.getName()));
    }

    @PostMapping("/{id}/close")
    public ApiResponse<Void> closeRoom(@PathVariable Long id) {
        roomService.closeRoom(id);
        return ApiResponse.ok();
    }

    /** 删除房间(先关闭会议, 再删除房间及关联记录) */
    @DeleteMapping("/{id}")
    public ApiResponse<Void> deleteRoom(@PathVariable Long id, Authentication authentication) {
        roomService.deleteRoom(id, authentication.getName());
        return ApiResponse.ok();
    }

    /** PC 端发送文字聊天消息 */
    @PostMapping("/{id}/chat")
    public ApiResponse<ChatMessageResponse> sendChat(@PathVariable Long id,
                                                     @Valid @RequestBody AdminChatRequest request,
                                                     Authentication authentication) {
        return ApiResponse.ok(chatService.sendFromAdmin(id, authentication.getName(), request.content()));
    }

    /** 近期聊天记录(时间正序) */
    @GetMapping("/{id}/chat")
    public ApiResponse<List<ChatMessageResponse>> chatHistory(@PathVariable Long id) {
        return ApiResponse.ok(chatService.recentByRoomId(id));
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
