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
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

import com.doommeeting.server.dto.DashboardDtos.TrendPoint;

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

    /** 最近 N 天的点赞/新建房间趋势(曲线图数据) */
    @Transactional(readOnly = true)
    public List<TrendPoint> trends(int days) {
        LocalDate today = LocalDate.now();
        LocalDate startDate = today.minusDays(days - 1L);
        LocalDateTime start = startDate.atStartOfDay();

        Map<LocalDate, Long> likesByDay = likeRepository.findByLikedAtAfter(start).stream()
                .collect(Collectors.groupingBy(
                        like -> like.getLikedAt().toLocalDate(), Collectors.counting()));
        Map<LocalDate, Long> roomsByDay = roomRepository.findByCreatedAtAfter(start).stream()
                .collect(Collectors.groupingBy(
                        room -> room.getCreatedAt().toLocalDate(), Collectors.counting()));

        DateTimeFormatter formatter = DateTimeFormatter.ofPattern("MM-dd");
        List<TrendPoint> points = new ArrayList<>();
        for (LocalDate date = startDate; !date.isAfter(today); date = date.plusDays(1)) {
            points.add(new TrendPoint(
                    date.format(formatter),
                    likesByDay.getOrDefault(date, 0L),
                    roomsByDay.getOrDefault(date, 0L)));
        }
        return points;
    }
}
