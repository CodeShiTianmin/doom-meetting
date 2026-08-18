package com.doommeeting.server;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.scheduling.annotation.EnableScheduling;

@EnableScheduling
@SpringBootApplication
public class MeetingServerApplication {

    public static void main(String[] args) {
        SpringApplication.run(MeetingServerApplication.class, args);
    }
}
