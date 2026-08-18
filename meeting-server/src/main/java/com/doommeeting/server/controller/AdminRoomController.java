package com.doommeeting.server.controller;

import com.doommeeting.server.common.ApiResponse;
import com.doommeeting.server.dto.LikeDtos.LikeRecordResponse;
import com.doommeeting.server.dto.RoomDtos.*;
import com.doommeeting.server.service.LikeService;
import com.doommeeting.server.service.LiveKitTokenService;
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
        return ApiResponse.ok(roomService.castContent(id, request.contentId(), authentication.getName()));
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
