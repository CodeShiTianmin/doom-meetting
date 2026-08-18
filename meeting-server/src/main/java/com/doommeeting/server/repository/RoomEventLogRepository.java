package com.doommeeting.server.repository;

import com.doommeeting.server.entity.Room;
import com.doommeeting.server.entity.RoomEventLog;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface RoomEventLogRepository extends JpaRepository<RoomEventLog, Long> {

    List<RoomEventLog> findTop200ByRoomOrderByCreatedAtDesc(Room room);
}
