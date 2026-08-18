package com.doommeeting.server.service;

import com.doommeeting.server.common.BusinessException;
import com.doommeeting.server.dto.CastScheduleDtos.CastScheduleRequest;
import com.doommeeting.server.dto.CastScheduleDtos.CastScheduleResponse;
import com.doommeeting.server.entity.CastSchedule;
import com.doommeeting.server.entity.Room;
import com.doommeeting.server.enums.CastScheduleStatus;
import com.doommeeting.server.enums.RoomStatus;
import com.doommeeting.server.repository.CastScheduleRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.List;

/**
 * 定时投放计划: 不同时间选择不同内容投给不同房间, 多房并行不串音不串频。
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class CastScheduleService {

    private final CastScheduleRepository scheduleRepository;
    private final RoomService roomService;
    private final ContentService contentService;

    @Transactional
    public CastScheduleResponse create(CastScheduleRequest request, String createdBy) {
        Room room = roomService.getRoomById(request.roomId());
        if (room.getStatus() == RoomStatus.CLOSED) {
            throw new BusinessException("房间已关闭, 无法创建投放计划");
        }
        CastSchedule schedule = new CastSchedule();
        schedule.setRoom(room);
        schedule.setContent(contentService.getById(request.contentId()));
        schedule.setCastAt(request.castAt());
        schedule.setNote(request.note());
        schedule.setCreatedBy(createdBy);
        scheduleRepository.save(schedule);
        return toResponse(schedule);
    }

    @Transactional
    public CastScheduleResponse cancel(Long id) {
        CastSchedule schedule = scheduleRepository.findById(id)
                .orElseThrow(() -> new BusinessException(404, "投放计划不存在"));
        if (schedule.getStatus() != CastScheduleStatus.PENDING) {
            throw new BusinessException("仅待执行的计划可取消");
        }
        schedule.setStatus(CastScheduleStatus.CANCELLED);
        scheduleRepository.save(schedule);
        return toResponse(schedule);
    }

    @Transactional(readOnly = true)
    public List<CastScheduleResponse> listAll() {
        return scheduleRepository.findAllByOrderByCastAtDesc().stream()
                .map(this::toResponse).toList();
    }

    /** 由调度器周期调用: 执行到期的投放计划 */
    @Transactional
    public void executeDueSchedules() {
        List<CastSchedule> due = scheduleRepository
                .findByStatusAndCastAtLessThanEqual(CastScheduleStatus.PENDING, LocalDateTime.now());
        for (CastSchedule schedule : due) {
            try {
                roomService.castContent(
                        schedule.getRoom().getId(),
                        schedule.getContent().getId(),
                        "定时投放计划#" + schedule.getId());
                schedule.setStatus(CastScheduleStatus.EXECUTED);
                schedule.setExecutedAt(LocalDateTime.now());
            } catch (Exception e) {
                log.warn("投放计划 {} 执行失败: {}", schedule.getId(), e.getMessage());
                schedule.setStatus(CastScheduleStatus.FAILED);
                schedule.setNote((schedule.getNote() == null ? "" : schedule.getNote() + " | ")
                        + "执行失败: " + e.getMessage());
            }
            scheduleRepository.save(schedule);
        }
    }

    private CastScheduleResponse toResponse(CastSchedule schedule) {
        return new CastScheduleResponse(
                schedule.getId(),
                schedule.getRoom().getId(),
                schedule.getRoom().getRoomCode(),
                schedule.getRoom().getName(),
                schedule.getContent().getId(),
                schedule.getContent().getName(),
                schedule.getCastAt(),
                schedule.getStatus().name(),
                schedule.getExecutedAt(),
                schedule.getNote(),
                schedule.getCreatedBy(),
                schedule.getCreatedAt());
    }
}
