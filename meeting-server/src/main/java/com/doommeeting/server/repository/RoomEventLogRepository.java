package com.doommeeting.server.repository;

import com.doommeeting.server.entity.Room;
import com.doommeeting.server.entity.RoomEventLog;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;

public interface RoomEventLogRepository extends JpaRepository<RoomEventLog, Long> {

    List<RoomEventLog> findTop200ByRoomOrderByCreatedAtDesc(Room room);

    /** 批量 SQL 删除, 不加载实体, 避免历史脏数据(如未知枚举值)导致删除失败 */
    @Modifying
    @Query("delete from RoomEventLog e where e.room = :room")
    void deleteByRoom(@Param("room") Room room);
}
