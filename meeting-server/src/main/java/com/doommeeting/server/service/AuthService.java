package com.doommeeting.server.service;

import com.doommeeting.server.common.BusinessException;
import com.doommeeting.server.dto.AuthDtos.LoginRequest;
import com.doommeeting.server.dto.AuthDtos.LoginResponse;
import com.doommeeting.server.entity.UserAccount;
import com.doommeeting.server.repository.UserAccountRepository;
import com.doommeeting.server.security.JwtService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.ApplicationRunner;
import org.springframework.context.annotation.Bean;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;

@Slf4j
@Service
@RequiredArgsConstructor
public class AuthService {

    private final UserAccountRepository userAccountRepository;
    private final PasswordEncoder passwordEncoder;
    private final JwtService jwtService;

    @Value("${default-admin.username}")
    private String defaultAdminUsername;

    @Value("${default-admin.password}")
    private String defaultAdminPassword;

    @Value("${default-admin.display-name}")
    private String defaultAdminDisplayName;

    public LoginResponse login(LoginRequest request) {
        UserAccount user = userAccountRepository.findByUsername(request.username())
                .orElseThrow(() -> new BusinessException(401, "用户名或密码错误"));
        if (!passwordEncoder.matches(request.password(), user.getPasswordHash())) {
            throw new BusinessException(401, "用户名或密码错误");
        }
        String token = jwtService.generateToken(user.getUsername(), user.getRole());
        return new LoginResponse(token, user.getUsername(), user.getDisplayName(), user.getRole());
    }

    /** 首次启动时初始化默认公司账号 */
    @Bean
    public ApplicationRunner initDefaultAdmin() {
        return args -> {
            if (userAccountRepository.findByUsername(defaultAdminUsername).isEmpty()) {
                UserAccount admin = new UserAccount();
                admin.setUsername(defaultAdminUsername);
                admin.setPasswordHash(passwordEncoder.encode(defaultAdminPassword));
                admin.setDisplayName(defaultAdminDisplayName);
                admin.setRole("ADMIN");
                userAccountRepository.save(admin);
                log.info("已初始化默认公司账号: {}", defaultAdminUsername);
            }
        };
    }
}
