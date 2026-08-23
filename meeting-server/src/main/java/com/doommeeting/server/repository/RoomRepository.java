package com.doommeeting.server.repository;

import com.doommeeting.server.entity.Room;
import com.doommeeting.server.enums.RoomStatus;
import jakarta.persistence.LockModeType;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

public interface RoomRepository extends JpaRepository<Room, Long> {

    Optional<Room> findByRoomCode(String roomCode);

    /** 行级悲观锁: 播放指令序号自增等需要串行化的更新使用(不依赖 JVM 内锁, 多实例亦安全) */
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select r from Room r where r.roomCode = :roomCode")
    Optional<Room> findByRoomCodeForUpdate(@Param("roomCode") String roomCode);

    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select r from Room r where r.id = :id")
    Optional<Room> findByIdForUpdate(@Param("id") Long id);

    List<Room> findByStatusOrderByCreatedAtDesc(RoomStatus status);

    List<Room> findAllByOrderByCreatedAtDesc();

    List<Room> findByStatusAndMeetingEndAtBefore(RoomStatus status, LocalDateTime time);

    List<Room> findByStatusIn(List<RoomStatus> statuses);

    long countByStatus(RoomStatus status);

    long countByUnderstaffedAlertTrueAndStatusNot(RoomStatus status);

    List<Room> findByCreatedAtAfter(LocalDateTime time);

    List<Room> findByStatusAndScheduledStartAtBefore(RoomStatus status, LocalDateTime time);
}
