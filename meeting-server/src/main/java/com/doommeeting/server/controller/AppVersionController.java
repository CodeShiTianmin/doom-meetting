package com.doommeeting.server.controller;

import com.doommeeting.server.common.ApiResponse;
import com.doommeeting.server.config.AppProperties;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.HashMap;
import java.util.Map;

/**
 * App 版本检查接口: APK 私发分发, App 启动时检查是否有新版本并提示下载
 */
@RestController
@RequestMapping("/api/app")
@RequiredArgsConstructor
public class AppVersionController {

    private final AppProperties properties;

    @GetMapping("/version")
    public ApiResponse<Map<String, Object>> version(
            @RequestParam(required = false, defaultValue = "0") int currentVersionCode) {
        AppProperties.MobileApp app = properties.getMobileApp();
        Map<String, Object> result = new HashMap<>();
        result.put("latestVersionCode", app.getLatestVersionCode());
        result.put("latestVersionName", app.getLatestVersionName());
        result.put("apkDownloadUrl", app.getApkDownloadUrl());
        result.put("releaseNotes", app.getReleaseNotes());
        result.put("updateAvailable", currentVersionCode < app.getLatestVersionCode());
        result.put("forceUpdate", currentVersionCode < app.getMinSupportedVersionCode());
        return ApiResponse.ok(result);
    }
}
