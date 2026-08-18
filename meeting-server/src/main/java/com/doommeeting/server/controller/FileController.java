package com.doommeeting.server.controller;

import com.doommeeting.server.common.BusinessException;
import com.doommeeting.server.entity.ContentItem;
import com.doommeeting.server.service.ContentService;
import com.doommeeting.server.service.FileStorageService;
import lombok.RequiredArgsConstructor;
import org.springframework.core.io.Resource;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.util.UriUtils;

import java.nio.charset.StandardCharsets;

/**
 * 投放文件下载/在线打开: 手机端、PC 端、管理网页统一通过该接口获取真实文件
 */
@RestController
@RequestMapping("/api/files")
@RequiredArgsConstructor
public class FileController {

    private final ContentService contentService;
    private final FileStorageService fileStorageService;

    @GetMapping("/{contentId}")
    public ResponseEntity<Resource> download(@PathVariable Long contentId) {
        ContentItem content = contentService.getById(contentId);
        if (content.getStoragePath() == null) {
            throw new BusinessException(404, "文件不存在或已随会议结束删除");
        }
        Resource resource = fileStorageService.loadAsResource(content.getStoragePath());
        String mimeType = content.getMimeType() == null
                ? MediaType.APPLICATION_OCTET_STREAM_VALUE : content.getMimeType();
        String encodedName = UriUtils.encode(content.getName(), StandardCharsets.UTF_8);
        return ResponseEntity.ok()
                .contentType(MediaType.parseMediaType(mimeType))
                .header(HttpHeaders.CONTENT_DISPOSITION,
                        "inline; filename*=UTF-8''" + encodedName)
                .header(HttpHeaders.ACCEPT_RANGES, "bytes")
                .body(resource);
    }
}
