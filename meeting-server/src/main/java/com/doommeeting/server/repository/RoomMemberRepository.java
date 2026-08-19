package com.doommeeting.server.repository;

import com.doommeeting.server.entity.Room;
import com.doommeeting.server.entity.RoomMember;
import org.springframework.data.jpa.repository.JpaRepository;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

public interface RoomMemberRepository extends JpaRepository<RoomMember, Long> {

    List<RoomMember> findByRoomOrderByJoinedAtAsc(Room room);

    List<RoomMember> findByOnlineTrueAndLastHeartbeatAtBefore(LocalDateTime threshold);

    List<RoomMember> findByRoomAndOnlineTrue(Room room);

    List<RoomMember> findByRoomAndOnlineFalse(Room room);

    long countByRoomAndOnlineTrue(Room room);

    Optional<RoomMember> findByRoomAndIdentity(Room room, String identity);
}
