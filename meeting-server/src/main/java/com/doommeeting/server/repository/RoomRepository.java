package com.doommeeting.server.repository;

import com.doommeeting.server.entity.Room;
import com.doommeeting.server.enums.RoomStatus;
import org.springframework.data.jpa.repository.JpaRepository;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

public interface RoomRepository extends JpaRepository<Room, Long> {

    Optional<Room> findByRoomCode(String roomCode);

    List<Room> findByStatusOrderByCreatedAtDesc(RoomStatus status);

    List<Room> findAllByOrderByCreatedAtDesc();

    List<Room> findByStatusAndMeetingEndAtBefore(RoomStatus status, LocalDateTime time);

    List<Room> findByStatusIn(List<RoomStatus> statuses);

    long countByStatus(RoomStatus status);

    long countByUnderstaffedAlertTrueAndStatusNot(RoomStatus status);

    List<Room> findByCreatedAtAfter(LocalDateTime time);

    List<Room> findByStatusAndScheduledStartAtBefore(RoomStatus status, LocalDateTime time);
}
