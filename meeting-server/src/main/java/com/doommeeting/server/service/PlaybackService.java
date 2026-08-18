package com.doommeeting.server.service;

import com.doommeeting.server.common.BusinessException;
import com.doommeeting.server.dto.MobileDtos.PlaybackControlRequest;
import com.doommeeting.server.entity.Room;
import com.doommeeting.server.entity.RoomMember;
import com.doommeeting.server.enums.PlaybackAction;
import com.doommeeting.server.enums.PlaybackState;
import com.doommeeting.server.enums.RoomEventType;
import com.doommeeting.server.enums.RoomStatus;
import com.doommeeting.server.repository.RoomMemberRepository;
import com.doommeeting.server.repository.RoomRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.HashMap;
import java.util.Map;

/**
 * 播放控制: 房间运行中, 手机端可执行 开始播放/暂停/拖动进度条;
 * 明暗、音量为手机本地调节(不影响另一客户端), 仅上报记录。
 * 控制指令带序号, 后端串行转发, 按最后指令执行并广播权威状态,
 * 解决两客户端同时操作冲突。
 */
@Service
@RequiredArgsConstructor
public class PlaybackService {

    private final RoomRepository roomRepository;
    private final RoomMemberRepository memberRepository;
    private final RoomService roomService;
    private final EventLogService eventLogService;
    private final NotificationService notificationService;

    @Transactional
    public synchronized Map<String, Object> control(String roomCode, PlaybackControlRequest request) {
        Room room = roomService.getRoomByCode(roomCode);
        if (room.getStatus() != RoomStatus.RUNNING) {
            throw new BusinessException("房间未运行, 无法进行播放控制");
        }
        RoomMember member = memberRepository.findByRoomAndIdentity(room, request.identity())
                .orElseThrow(() -> new BusinessException(403, "非房间成员, 禁止操作"));
        if (!member.getOnline()) {
            throw new BusinessException(403, "成员已离会, 禁止操作");
        }

        PlaybackAction action;
        try {
            action = PlaybackAction.valueOf(request.action().toUpperCase());
        } catch (IllegalArgumentException e) {
            throw new BusinessException("不支持的播放指令: " + request.action());
        }

        boolean sharedControl = action == PlaybackAction.PLAY
                || action == PlaybackAction.PAUSE
                || action == PlaybackAction.SEEK;

        if (sharedControl) {
            // 序号过期的指令丢弃(两客户端同时操作时按最后指令为准)
            if (request.seq() <= room.getLastCommandSeq()) {
                return authoritativeState(room, "指令序号过期, 已按最新状态同步");
            }
            room.setLastCommandSeq(request.seq());
            switch (action) {
                case PLAY -> room.setPlaybackState(PlaybackState.PLAYING);
                case PAUSE -> room.setPlaybackState(PlaybackState.PAUSED);
                case SEEK -> {
                    if (request.positionSeconds() == null) {
                        throw new BusinessException("SEEK 指令必须携带进度");
                    }
                }
                default -> { }
            }
            if (request.positionSeconds() != null) {
                room.setPlaybackPositionSeconds(Math.max(0, request.positionSeconds()));
            }
            room.setPlaybackUpdatedAt(LocalDateTime.now());
            roomRepository.save(room);
        }

        String detail = member.getNickname() + " " + describe(action, request);
        eventLogService.log(room, RoomEventType.PLAYBACK_CONTROL, detail);

        Map<String, Object> payload = new HashMap<>();
        payload.put("action", action.name());
        payload.put("identity", member.getIdentity());
        payload.put("nickname", member.getNickname());
        payload.put("seq", room.getLastCommandSeq());
        payload.put("playbackState", room.getPlaybackState().name());
        payload.put("positionSeconds", room.getPlaybackPositionSeconds());
        if (request.value() != null) {
            payload.put("value", request.value());
        }
        // 共享指令广播到房间(另一客户端同步) + PC 端播放器执行; 本地调节仅通知 PC 端展示
        if (sharedControl) {
            notificationService.pushToRoomAndAdmin(room.getRoomCode(), "PLAYBACK_CONTROL", payload);
        } else {
            notificationService.pushToAdmin("PLAYBACK_CONTROL", room.getRoomCode(), payload);
        }
        return authoritativeState(room, null);
    }

    private Map<String, Object> authoritativeState(Room room, String message) {
        Map<String, Object> state = new HashMap<>();
        state.put("playbackState", room.getPlaybackState().name());
        state.put("positionSeconds", room.getPlaybackPositionSeconds());
        state.put("seq", room.getLastCommandSeq());
        if (message != null) {
            state.put("message", message);
        }
        return state;
    }

    private String describe(PlaybackAction action, PlaybackControlRequest request) {
        return switch (action) {
            case PLAY -> "开始播放";
            case PAUSE -> "暂停播放";
            case SEEK -> "拖动进度条至 " + request.positionSeconds() + " 秒";
            case BRIGHTNESS -> "调节明暗至 " + request.value() + "(本地)";
            case VOLUME -> "调节音量至 " + request.value() + "(本地)";
        };
    }
}
