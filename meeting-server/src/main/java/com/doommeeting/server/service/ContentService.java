package com.doommeeting.server.service;

import com.doommeeting.server.common.BusinessException;
import com.doommeeting.server.dto.ContentDtos.ContentResponse;
import com.doommeeting.server.entity.ContentItem;
import com.doommeeting.server.repository.ContentItemRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.multipart.MultipartFile;

import java.util.List;

/**
 * 投放内容管理: 仅支持真实文件上传存储(UPLOADED_FILE), 会议结束后自动删除
 */
@Service
@RequiredArgsConstructor
public class ContentService {

    private final ContentItemRepository contentItemRepository;
    private final FileStorageService fileStorageService;
    private final FileAccessTokenService fileAccessTokenService;

    /** 上传真实文件并登记为投放内容, 可关联房间(会议结束后自动删除) */
    @Transactional
    public ContentResponse upload(MultipartFile file, Long roomId, String createdBy) {
        if (file == null || file.isEmpty()) {
            throw new BusinessException("上传文件不能为空");
        }
        String storagePath = fileStorageService.store(file);
        ContentItem content = new ContentItem();
        String original = file.getOriginalFilename() == null ? "未命名文件" : file.getOriginalFilename();
        content.setName(original.length() > 128 ? original.substring(0, 128) : original);
        content.setType("UPLOADED_FILE");
        content.setStoragePath(storagePath);
        content.setFileSize(file.getSize());
        content.setMimeType(file.getContentType());
        content.setRoomId(roomId);
        content.setCreatedBy(createdBy);
        contentItemRepository.save(content);
        return toResponse(content);
    }

    /** 会议结束: 删除该房间关联的所有上传文件并禁用内容记录 */
    @Transactional
    public void deleteRoomFiles(Long roomId) {
        for (ContentItem content : contentItemRepository.findByRoomId(roomId)) {
            fileStorageService.delete(content.getStoragePath());
            content.setStoragePath(null);
            content.setEnabled(false);
            contentItemRepository.save(content);
        }
    }

    @Transactional
    public void delete(Long id) {
        ContentItem content = getById(id);
        fileStorageService.delete(content.getStoragePath());
        content.setStoragePath(null);
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

    /** 获取可投放内容: 必须启用且服务器文件仍存在 */
    public ContentItem getCastable(Long id) {
        ContentItem content = getById(id);
        if (!Boolean.TRUE.equals(content.getEnabled())) {
            throw new BusinessException("该内容已禁用, 无法投放");
        }
        if (content.getStoragePath() == null || content.getStoragePath().isBlank()) {
            throw new BusinessException("该内容文件已删除, 无法投放");
        }
        return content;
    }

    private ContentResponse toResponse(ContentItem content) {
        return new ContentResponse(
                content.getId(),
                content.getName(),
                content.getDescription(),
                content.getType(),
                content.getDurationSeconds(),
                fileUrlOf(content),
                content.getFileSize(),
                content.getMimeType(),
                content.getRoomId(),
                content.getEnabled(),
                content.getCreatedBy(),
                content.getCreatedAt());
    }

    /** 生成带短时效签名 token 的文件访问 URL */
    public String fileUrlOf(ContentItem content) {
        if (content.getStoragePath() == null) {
            return null;
        }
        return "/api/files/" + content.getId()
                + "?token=" + fileAccessTokenService.issueToken(content.getId());
    }
}
