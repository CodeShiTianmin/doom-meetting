package com.doommeeting.server.repository;

import com.doommeeting.server.entity.ContentItem;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface ContentItemRepository extends JpaRepository<ContentItem, Long> {

    List<ContentItem> findByEnabledTrueOrderByCreatedAtDesc();

    List<ContentItem> findAllByOrderByCreatedAtDesc();
}
