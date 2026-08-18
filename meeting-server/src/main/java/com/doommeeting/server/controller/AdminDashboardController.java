package com.doommeeting.server.controller;

import com.doommeeting.server.common.ApiResponse;
import com.doommeeting.server.dto.DashboardDtos.DashboardSummary;
import com.doommeeting.server.dto.LikeDtos.LikeRecordResponse;
import com.doommeeting.server.service.DashboardService;
import com.doommeeting.server.service.LikeService;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

/**
 * 管理端看板与全量点赞记录
 */
@RestController
@RequestMapping("/api/admin")
@RequiredArgsConstructor
public class AdminDashboardController {

    private final DashboardService dashboardService;
    private final LikeService likeService;

    @GetMapping("/dashboard/summary")
    public ApiResponse<DashboardSummary> summary() {
        return ApiResponse.ok(dashboardService.summary());
    }

    @GetMapping("/likes")
    public ApiResponse<List<LikeRecordResponse>> listAllLikes() {
        return ApiResponse.ok(likeService.listAll());
    }
}
