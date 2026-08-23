package com.doommeeting.server.repository;

import com.doommeeting.server.entity.ChatMessage;
import com.doommeeting.server.entity.Room;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface ChatMessageRepository extends JpaRepository<ChatMessage, Long> {

    List<ChatMessage> findTop100ByRoomOrderByCreatedAtDesc(Room room);
}
