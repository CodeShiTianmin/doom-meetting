package com.doommeeting.server.dto;

public class DashboardDtos {

    public record DashboardSummary(
            long totalRooms,
            long waitingRooms,
            long runningRooms,
            long closedRooms,
            long alertRooms,
            long totalLikes,
            long todayLikes) {
    }

    public record TrendPoint(
            String date,
            long likes,
            long rooms) {
    }
}
