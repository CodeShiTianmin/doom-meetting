package com.doommeeting.server.controller;

import com.doommeeting.server.common.ApiResponse;
import com.doommeeting.server.dto.DashboardDtos.DashboardSummary;
import com.doommeeting.server.dto.DashboardDtos.TrendPoint;
import org.springframework.web.bind.annotation.RequestParam;
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

    @GetMapping("/dashboard/trends")
    public ApiResponse<List<TrendPoint>> trends(@RequestParam(defaultValue = "7") int days) {
        return ApiResponse.ok(dashboardService.trends(Math.min(Math.max(days, 1), 90)));
    }

    @GetMapping("/likes")
    public ApiResponse<List<LikeRecordResponse>> listAllLikes() {
        return ApiResponse.ok(likeService.listAll());
    }
}
