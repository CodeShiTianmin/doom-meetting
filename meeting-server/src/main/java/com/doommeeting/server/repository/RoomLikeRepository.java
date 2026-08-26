package com.doommeeting.server.repository;

import com.doommeeting.server.entity.Room;
import com.doommeeting.server.entity.RoomLike;
import org.springframework.data.jpa.repository.JpaRepository;

import java.time.LocalDateTime;
import java.util.List;

public interface RoomLikeRepository extends JpaRepository<RoomLike, Long> {

    List<RoomLike> findByRoomOrderByLikedAtDesc(Room room);

    List<RoomLike> findAllByOrderByLikedAtDesc();

    long countByRoom(Room room);

    long countByLikedAtAfter(LocalDateTime time);

    List<RoomLike> findByLikedAtAfter(LocalDateTime time);

    long countByRoomAndMemberIdentity(Room room, String memberIdentity);

    void deleteByRoom(Room room);
}
