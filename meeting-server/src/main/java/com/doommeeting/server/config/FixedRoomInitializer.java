package com.doommeeting.server.config;

import com.doommeeting.server.entity.Room;
import com.doommeeting.server.enums.RoomEventType;
import com.doommeeting.server.enums.RoomStatus;
import com.doommeeting.server.repository.RoomRepository;
import com.doommeeting.server.service.EventLogService;
import com.doommeeting.server.service.RoomService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.ApplicationRunner;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * 固定房间初始化: 启动时确保 1-N 号固定房间存在(默认 24 间), 并清理 1-N 之外的全部多余房间,
 * 保证系统中永远只有这 N 间固定房。
 * 固定房间不支持删除, 只支持"手动结束会议"重置回初始状态。
 * 摄像头权限默认关闭, 由 PC 端总览界面按房间开放。
 */
@Slf4j
@Configuration
@RequiredArgsConstructor
public class FixedRoomInitializer {

    private final RoomRepository roomRepository;
    private final RoomService roomService;
    private final EventLogService eventLogService;
    private final AppProperties properties;
    private final TransactionTemplate transactionTemplate;

    @Bean
    public ApplicationRunner initFixedRooms() {
        return args -> transactionTemplate.executeWithoutResult(status -> {
            int count = properties.getRoom().getFixedRoomCount();
            for (int no = 1; no <= count; no++) {
                String roomCode = String.valueOf(no);
                if (roomRepository.findByRoomCode(roomCode).isPresent()) {
                    continue;
                }
                Room room = new Room();
                room.setRoomCode(roomCode);
                room.setName(no + "号房间");
                room.setStatus(RoomStatus.WAITING);
                room.setDurationMinutes(properties.getRoom().getDefaultDurationMinutes());
                room.setMaxMembers(properties.getRoom().getMaxClients());
                room.setVideoCallEnabled(true);
                room.setCameraEnabled(false);
                room.setApprovalRequired(false);
                room.setCreatedBy("system");
                roomRepository.save(room);
                roomService.createSeatInvites(room);
                eventLogService.log(room, RoomEventType.ROOM_CREATED,
                        "固定房间初始化, 会议时长 " + room.getDurationMinutes() + " 分钟");
                log.info("固定房间 {} 初始化完成", roomCode);
            }
            int purged = roomService.purgeNonFixedRooms();
            if (purged > 0) {
                log.info("已清理 {} 间固定 1-{} 号房之外的多余房间", purged, count);
            }
        });
    }
}
