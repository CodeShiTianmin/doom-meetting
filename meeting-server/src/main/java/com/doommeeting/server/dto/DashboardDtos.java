package com.doommeeting.server.dto;

public class DashboardDtos {

    public record DashboardSummary(
            long totalRooms,
            long waitingRooms,
            long runningRooms,
            long closedRooms,
            long alertRooms,
            long totalLikes,
            long todayLikes,
            long totalContents,
            long pendingSchedules) {
    }

    public record TrendPoint(
            String date,
            long likes,
            long rooms) {
    }
}
