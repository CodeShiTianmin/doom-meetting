package com.doommeeting.server.controller;

import com.doommeeting.server.common.ApiResponse;
import com.doommeeting.server.dto.ContentDtos.ContentRequest;
import com.doommeeting.server.dto.ContentDtos.ContentResponse;
import com.doommeeting.server.service.ContentService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;

import java.util.List;

/**
 * 投放内容管理(元数据)
 */
@RestController
@RequestMapping("/api/admin/contents")
@RequiredArgsConstructor
public class AdminContentController {

    private final ContentService contentService;

    @PostMapping
    public ApiResponse<ContentResponse> create(@Valid @RequestBody ContentRequest request,
                                               Authentication authentication) {
        return ApiResponse.ok(contentService.create(request, authentication.getName()));
    }

    @GetMapping
    public ApiResponse<List<ContentResponse>> list(
            @RequestParam(defaultValue = "false") boolean includeDisabled) {
        return ApiResponse.ok(contentService.list(includeDisabled));
    }

    @PutMapping("/{id}")
    public ApiResponse<ContentResponse> update(@PathVariable Long id,
                                               @Valid @RequestBody ContentRequest request) {
        return ApiResponse.ok(contentService.update(id, request));
    }

    @DeleteMapping("/{id}")
    public ApiResponse<Void> delete(@PathVariable Long id) {
        contentService.delete(id);
        return ApiResponse.ok();
    }
}
