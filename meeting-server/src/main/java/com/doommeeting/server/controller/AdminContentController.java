package com.doommeeting.server.controller;

import com.doommeeting.server.common.ApiResponse;
import com.doommeeting.server.dto.ContentDtos.ContentResponse;
import com.doommeeting.server.service.ContentService;
import lombok.RequiredArgsConstructor;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

import java.util.List;

/**
 * 投放内容管理(仅上传文件)
 */
@RestController
@RequestMapping("/api/admin/contents")
@RequiredArgsConstructor
public class AdminContentController {

    private final ContentService contentService;

    /** 真实文件上传(管理网页/PC 端), 可关联房间以便会议结束后自动删除 */
    @PostMapping("/upload")
    public ApiResponse<ContentResponse> upload(@RequestParam("file") MultipartFile file,
                                               @RequestParam(required = false) Long roomId,
                                               Authentication authentication) {
        return ApiResponse.ok(contentService.upload(file, roomId, authentication.getName()));
    }

    @GetMapping
    public ApiResponse<List<ContentResponse>> list(
            @RequestParam(defaultValue = "false") boolean includeDisabled) {
        return ApiResponse.ok(contentService.list(includeDisabled));
    }

    @DeleteMapping("/{id}")
    public ApiResponse<Void> delete(@PathVariable Long id) {
        contentService.delete(id);
        return ApiResponse.ok();
    }
}
