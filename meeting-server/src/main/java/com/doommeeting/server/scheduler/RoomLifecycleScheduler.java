package com.doommeeting.server.scheduler;

import com.doommeeting.server.config.AppProperties;
import com.doommeeting.server.entity.Room;
import com.doommeeting.server.enums.CloseReason;
import com.doommeeting.server.enums.RoomEventType;
import com.doommeeting.server.enums.RoomStatus;
import com.doommeeting.server.repository.RoomRepository;
import com.doommeeting.server.service.EventLogService;
import com.doommeeting.server.service.MemberService;
import com.doommeeting.server.service.NotificationService;
import com.doommeeting.server.service.RoomService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.time.Duration;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;

/**
 * 房间生命周期调度:
 * 0. 心跳超时离线判定
 * 1. 缺人红灯预警: 创建房间(或成员离会)后缺人状态超过 3 分钟, 后台亮红灯
 * 2. 会议倒计时提醒: 剩余 5 分钟 / 1 分钟推送提醒
 * 3. 会议到期自动关闭
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class RoomLifecycleScheduler {

    private final RoomRepository roomRepository;
    private final RoomService roomService;
    private final MemberService memberService;
    private final EventLogService eventLogService;
    private final NotificationService notificationService;
    private final AppProperties properties;

    /**
     * 注意: tick 本身不开事务, 各步骤独立提交并隔离异常,
     * 避免单步失败将整个调度周期标记 rollback-only 一起回滚。
     */
    @Scheduled(fixedDelay = 5000)
    public void tick() {
        LocalDateTime now = LocalDateTime.now();
        runStep("预约开会", () -> roomService.activateScheduledRooms(now));
        runStep("心跳离线判定", () -> memberService.markStaleMembersOffline(now));
        runStep("缺人预警", () -> checkUnderstaffedAlerts(now));
        runStep("倒计时提醒", () -> checkCountdownReminders(now));
        runStep("到期关房", () -> autoCloseExpiredRooms(now));
    }

    private void runStep(String name, Runnable step) {
        try {
            step.run();
        } catch (Exception e) {
            log.warn("调度步骤[{}]执行失败: {}", name, e.getMessage(), e);
        }
    }

    /** 创建房间后超过 3 分钟缺人状态, 后台亮红灯预警 */
    private void checkUnderstaffedAlerts(LocalDateTime now) {
        List<Room> activeRooms = roomRepository.findByStatusIn(
                List.of(RoomStatus.WAITING, RoomStatus.RUNNING));
        int thresholdMinutes = properties.getRoom().getUnderstaffedAlertMinutes();
        for (Room room : activeRooms) {
            if (Boolean.TRUE.equals(room.getUnderstaffedAlert())) {
                continue;
            }
            LocalDateTime since = room.getUnderstaffedSince();
            if (since != null && Duration.between(since, now).toMinutes() >= thresholdMinutes) {
                room.setUnderstaffedAlert(true);
                roomRepository.save(room);
                eventLogService.log(room, RoomEventType.UNDERSTAFFED_ALERT,
                        "缺人状态超过 " + thresholdMinutes + " 分钟, 红灯预警");
                notificationService.pushToAdmin("UNDERSTAFFED_ALERT", room.getRoomCode(), Map.of(
                        "roomId", room.getId(),
                        "name", room.getName(),
                        "onlineCount", memberService.countOnline(room),
                        "maxMembers", memberService.maxMembersOf(room),
                        "understaffedSince", String.valueOf(since)));
                log.info("房间 {} 缺人红灯预警", room.getRoomCode());
            }
        }
    }

    /** 到期前向房间内推送倒计时提醒(剩余 5 分钟 / 1 分钟) */
    private void checkCountdownReminders(LocalDateTime now) {
        List<Room> runningRooms = roomRepository.findByStatusOrderByCreatedAtDesc(RoomStatus.RUNNING);
        for (Room room : runningRooms) {
            if (room.getMeetingEndAt() == null) {
                continue;
            }
            long remainingSeconds = Duration.between(now, room.getMeetingEndAt()).getSeconds();
            if (remainingSeconds <= 0) {
                continue;
            }
            if (remainingSeconds <= 60 && !room.getReminder1Sent()) {
                room.setReminder1Sent(true);
                room.setReminder5Sent(true);
                roomRepository.save(room);
                sendReminder(room, 1, remainingSeconds);
            } else if (remainingSeconds <= 300 && !room.getReminder5Sent()) {
                room.setReminder5Sent(true);
                roomRepository.save(room);
                sendReminder(room, 5, remainingSeconds);
            }
        }
    }

    private void sendReminder(Room room, int minutes, long remainingSeconds) {
        eventLogService.log(room, RoomEventType.COUNTDOWN_REMINDER,
                "会议剩余不足 " + minutes + " 分钟");
        notificationService.pushToRoomAndAdmin(room.getRoomCode(), "COUNTDOWN_REMINDER", Map.of(
                "remainingMinutes", minutes,
                "remainingSeconds", remainingSeconds));
    }

    /** 会议时长到期, 自动关闭房间 */
    private void autoCloseExpiredRooms(LocalDateTime now) {
        List<Room> expired = roomRepository.findByStatusAndMeetingEndAtBefore(RoomStatus.RUNNING, now);
        for (Room room : expired) {
            log.info("房间 {} 会议时长到期, 自动关闭", room.getRoomCode());
            roomService.closeRoomInternal(room, CloseReason.TIMEOUT);
        }
    }
}
