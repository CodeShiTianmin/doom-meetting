package com.doommeeting.server.repository;

import com.doommeeting.server.entity.CastSchedule;
import com.doommeeting.server.enums.CastScheduleStatus;
import org.springframework.data.jpa.repository.JpaRepository;

import java.time.LocalDateTime;
import java.util.List;

public interface CastScheduleRepository extends JpaRepository<CastSchedule, Long> {

    List<CastSchedule> findByStatusAndCastAtLessThanEqual(CastScheduleStatus status, LocalDateTime time);

    List<CastSchedule> findAllByOrderByCastAtDesc();
}
