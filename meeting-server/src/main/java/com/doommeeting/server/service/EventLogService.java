package com.doommeeting.server.service;

import com.doommeeting.server.entity.Room;
import com.doommeeting.server.entity.RoomEventLog;
import com.doommeeting.server.enums.RoomEventType;
import com.doommeeting.server.repository.RoomEventLogRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

import java.util.List;

@Service
@RequiredArgsConstructor
public class EventLogService {

    private final RoomEventLogRepository eventLogRepository;

    public void log(Room room, RoomEventType type, String detail) {
        RoomEventLog log = new RoomEventLog();
        log.setRoom(room);
        log.setType(type);
        log.setDetail(detail);
        eventLogRepository.save(log);
    }

    public List<RoomEventLog> recentEvents(Room room) {
        return eventLogRepository.findTop200ByRoomOrderByCreatedAtDesc(room);
    }
}
