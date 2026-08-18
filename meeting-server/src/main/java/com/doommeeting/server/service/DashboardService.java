package com.doommeeting.server.service;

import com.doommeeting.server.dto.DashboardDtos.DashboardSummary;
import com.doommeeting.server.enums.CastScheduleStatus;
import com.doommeeting.server.enums.RoomStatus;
import com.doommeeting.server.repository.CastScheduleRepository;
import com.doommeeting.server.repository.ContentItemRepository;
import com.doommeeting.server.repository.RoomLikeRepository;
import com.doommeeting.server.repository.RoomRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.time.LocalDateTime;

@Service
@RequiredArgsConstructor
public class DashboardService {

    private final RoomRepository roomRepository;
    private final RoomLikeRepository likeRepository;
    private final ContentItemRepository contentItemRepository;
    private final CastScheduleRepository scheduleRepository;

    @Transactional(readOnly = true)
    public DashboardSummary summary() {
        LocalDateTime todayStart = LocalDate.now().atStartOfDay();
        return new DashboardSummary(
                roomRepository.count(),
                roomRepository.countByStatus(RoomStatus.WAITING),
                roomRepository.countByStatus(RoomStatus.RUNNING),
                roomRepository.countByStatus(RoomStatus.CLOSED),
                roomRepository.countByUnderstaffedAlertTrueAndStatusNot(RoomStatus.CLOSED),
                likeRepository.count(),
                likeRepository.countByLikedAtAfter(todayStart),
                contentItemRepository.findByEnabledTrueOrderByCreatedAtDesc().size(),
                scheduleRepository.findByStatusAndCastAtLessThanEqual(
                        CastScheduleStatus.PENDING, LocalDateTime.now().plusYears(100)).size());
    }
}
