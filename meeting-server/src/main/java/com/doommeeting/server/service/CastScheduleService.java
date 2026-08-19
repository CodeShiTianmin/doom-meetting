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
import org.springframework.transaction.support.TransactionTemplate;

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
    private final TransactionTemplate transactionTemplate;

    @Transactional
    public CastScheduleResponse create(CastScheduleRequest request, String createdBy) {
        Room room = roomService.getRoomById(request.roomId());
        if (room.getStatus() == RoomStatus.CLOSED) {
            throw new BusinessException("房间已关闭, 无法创建投放计划");
        }
        CastSchedule schedule = new CastSchedule();
        schedule.setRoom(room);
        schedule.setContent(contentService.getCastable(request.contentId()));
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

    /**
     * 由调度器周期调用: 执行到期的投放计划。
     * 本方法不开事务, 每个计划的投放在 castContent 自身事务中执行,
     * 失败状态在独立事务中落库, 避免单个计划失败把整个调度事务标记 rollback-only。
     */
    public void executeDueSchedules() {
        List<CastSchedule> due = scheduleRepository
                .findByStatusAndCastAtLessThanEqual(CastScheduleStatus.PENDING, LocalDateTime.now());
        for (CastSchedule schedule : due) {
            try {
                roomService.castContent(
                        schedule.getRoom().getId(),
                        schedule.getContent().getId(),
                        "定时投放计划#" + schedule.getId(),
                        true);
                markExecuted(schedule.getId());
            } catch (Exception e) {
                log.warn("投放计划 {} 执行失败: {}", schedule.getId(), e.getMessage());
                markFailed(schedule.getId(), e.getMessage());
            }
        }
    }

    /** 独立事务落库(TransactionTemplate 避免同类自调用不走代理的问题) */
    private void markExecuted(Long scheduleId) {
        transactionTemplate.executeWithoutResult(status ->
                scheduleRepository.findById(scheduleId).ifPresent(schedule -> {
                    schedule.setStatus(CastScheduleStatus.EXECUTED);
                    schedule.setExecutedAt(LocalDateTime.now());
                    scheduleRepository.save(schedule);
                }));
    }

    private void markFailed(Long scheduleId, String reason) {
        transactionTemplate.executeWithoutResult(status ->
                scheduleRepository.findById(scheduleId).ifPresent(schedule -> {
                    schedule.setStatus(CastScheduleStatus.FAILED);
                    schedule.setNote((schedule.getNote() == null ? "" : schedule.getNote() + " | ")
                            + "执行失败: " + reason);
                    scheduleRepository.save(schedule);
                }));
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
