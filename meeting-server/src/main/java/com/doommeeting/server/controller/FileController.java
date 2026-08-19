package com.doommeeting.server.controller;

import com.doommeeting.server.common.BusinessException;
import com.doommeeting.server.entity.ContentItem;
import com.doommeeting.server.service.ContentService;
import com.doommeeting.server.service.FileAccessTokenService;
import com.doommeeting.server.service.FileStorageService;
import lombok.RequiredArgsConstructor;
import org.springframework.core.io.Resource;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.util.UriUtils;

import java.nio.charset.StandardCharsets;

/**
 * 投放文件下载/在线打开: 手机端、PC 端、管理网页统一通过该接口获取真实文件。
 * 访问需携带短时效签名 token(投放事件/房间状态里随文件 URL 下发), 管理员 JWT 亦可直接访问。
 */
@RestController
@RequestMapping("/api/files")
@RequiredArgsConstructor
public class FileController {

    private final ContentService contentService;
    private final FileStorageService fileStorageService;
    private final FileAccessTokenService fileAccessTokenService;

    @GetMapping("/{contentId}")
    public ResponseEntity<Resource> download(@PathVariable Long contentId,
                                             @RequestParam(required = false) String token) {
        if (!isAdmin() && !fileAccessTokenService.validate(contentId, token)) {
            throw new BusinessException(403, "文件访问凭证无效或已过期");
        }
        ContentItem content = contentService.getById(contentId);
        if (content.getStoragePath() == null) {
            throw new BusinessException(404, "文件不存在或已随会议结束删除");
        }
        Resource resource = fileStorageService.loadAsResource(content.getStoragePath());
        MediaType mediaType = MediaType.APPLICATION_OCTET_STREAM;
        if (content.getMimeType() != null) {
            try {
                mediaType = MediaType.parseMediaType(content.getMimeType());
            } catch (RuntimeException ignored) {
                // 客户端上报的非法 MIME 回退为二进制流
            }
        }
        String encodedName = UriUtils.encode(content.getName(), StandardCharsets.UTF_8);
        return ResponseEntity.ok()
                .contentType(mediaType)
                .header(HttpHeaders.CONTENT_DISPOSITION,
                        "inline; filename*=UTF-8''" + encodedName)
                .header(HttpHeaders.ACCEPT_RANGES, "bytes")
                .body(resource);
    }

    private boolean isAdmin() {
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        return authentication != null && authentication.getAuthorities().stream()
                .anyMatch(a -> "ROLE_ADMIN".equals(a.getAuthority()));
    }
}
