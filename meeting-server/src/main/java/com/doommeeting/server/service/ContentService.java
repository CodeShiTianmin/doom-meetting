package com.doommeeting.server.service;

import com.doommeeting.server.common.BusinessException;
import com.doommeeting.server.dto.ContentDtos.ContentRequest;
import com.doommeeting.server.dto.ContentDtos.ContentResponse;
import com.doommeeting.server.entity.ContentItem;
import com.doommeeting.server.repository.ContentItemRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

/**
 * 投放内容管理(仅元数据, 媒体文件保留在本地 PC, 不上云)
 */
@Service
@RequiredArgsConstructor
public class ContentService {

    private final ContentItemRepository contentItemRepository;

    @Transactional
    public ContentResponse create(ContentRequest request, String createdBy) {
        ContentItem content = new ContentItem();
        apply(content, request);
        content.setCreatedBy(createdBy);
        contentItemRepository.save(content);
        return toResponse(content);
    }

    @Transactional
    public ContentResponse update(Long id, ContentRequest request) {
        ContentItem content = getById(id);
        apply(content, request);
        contentItemRepository.save(content);
        return toResponse(content);
    }

    @Transactional
    public void delete(Long id) {
        ContentItem content = getById(id);
        content.setEnabled(false);
        contentItemRepository.save(content);
    }

    @Transactional(readOnly = true)
    public List<ContentResponse> list(boolean includeDisabled) {
        List<ContentItem> items = includeDisabled
                ? contentItemRepository.findAllByOrderByCreatedAtDesc()
                : contentItemRepository.findByEnabledTrueOrderByCreatedAtDesc();
        return items.stream().map(this::toResponse).toList();
    }

    public ContentItem getById(Long id) {
        return contentItemRepository.findById(id)
                .orElseThrow(() -> new BusinessException(404, "投放内容不存在"));
    }

    private void apply(ContentItem content, ContentRequest request) {
        content.setName(request.name());
        content.setDescription(request.description());
        if (request.type() != null) {
            content.setType(request.type());
        }
        content.setLocalPath(request.localPath());
        content.setDurationSeconds(request.durationSeconds());
        if (request.enabled() != null) {
            content.setEnabled(request.enabled());
        }
    }

    private ContentResponse toResponse(ContentItem content) {
        return new ContentResponse(
                content.getId(),
                content.getName(),
                content.getDescription(),
                content.getType(),
                content.getLocalPath(),
                content.getDurationSeconds(),
                content.getEnabled(),
                content.getCreatedBy(),
                content.getCreatedAt());
    }
}
