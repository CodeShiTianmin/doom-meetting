package com.doommeeting.server.controller;

import com.doommeeting.server.common.ApiResponse;
import com.doommeeting.server.dto.CastScheduleDtos.CastScheduleRequest;
import com.doommeeting.server.dto.CastScheduleDtos.CastScheduleResponse;
import com.doommeeting.server.service.CastScheduleService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;

import java.util.List;

/**
 * 定时投放计划: 不同时间不同内容投给不同房间(并行, 不串音不串频)
 */
@RestController
@RequestMapping("/api/admin/cast-schedules")
@RequiredArgsConstructor
public class AdminCastScheduleController {

    private final CastScheduleService castScheduleService;

    @PostMapping
    public ApiResponse<CastScheduleResponse> create(@Valid @RequestBody CastScheduleRequest request,
                                                    Authentication authentication) {
        return ApiResponse.ok(castScheduleService.create(request, authentication.getName()));
    }

    @GetMapping
    public ApiResponse<List<CastScheduleResponse>> list() {
        return ApiResponse.ok(castScheduleService.listAll());
    }

    @PostMapping("/{id}/cancel")
    public ApiResponse<CastScheduleResponse> cancel(@PathVariable Long id) {
        return ApiResponse.ok(castScheduleService.cancel(id));
    }
}
