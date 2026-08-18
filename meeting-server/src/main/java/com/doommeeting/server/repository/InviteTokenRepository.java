package com.doommeeting.server.repository;

import com.doommeeting.server.entity.InviteToken;
import com.doommeeting.server.entity.Room;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;

public interface InviteTokenRepository extends JpaRepository<InviteToken, Long> {

    Optional<InviteToken> findByToken(String token);

    List<InviteToken> findByRoom(Room room);
}
