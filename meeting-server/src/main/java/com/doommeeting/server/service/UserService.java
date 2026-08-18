package com.doommeeting.server.service;

import com.doommeeting.server.common.BusinessException;
import com.doommeeting.server.dto.UserDtos.UserCreateRequest;
import com.doommeeting.server.dto.UserDtos.UserResponse;
import com.doommeeting.server.dto.UserDtos.UserUpdateRequest;
import com.doommeeting.server.entity.UserAccount;
import com.doommeeting.server.repository.UserAccountRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

/**
 * 公司账号管理(添加/管理用户)
 */
@Service
@RequiredArgsConstructor
public class UserService {

    private final UserAccountRepository userAccountRepository;
    private final PasswordEncoder passwordEncoder;

    @Transactional(readOnly = true)
    public List<UserResponse> list() {
        return userAccountRepository.findAll().stream().map(this::toResponse).toList();
    }

    @Transactional
    public UserResponse create(UserCreateRequest request) {
        if (userAccountRepository.findByUsername(request.username()).isPresent()) {
            throw new BusinessException(409, "用户名已存在");
        }
        UserAccount user = new UserAccount();
        user.setUsername(request.username());
        user.setPasswordHash(passwordEncoder.encode(request.password()));
        user.setDisplayName(request.displayName());
        user.setRole(request.role() == null || request.role().isBlank() ? "ADMIN" : request.role());
        userAccountRepository.save(user);
        return toResponse(user);
    }

    @Transactional
    public UserResponse update(Long id, UserUpdateRequest request) {
        UserAccount user = getById(id);
        if (request.displayName() != null) {
            user.setDisplayName(request.displayName());
        }
        if (request.role() != null && !request.role().isBlank()) {
            user.setRole(request.role());
        }
        if (request.password() != null && !request.password().isBlank()) {
            user.setPasswordHash(passwordEncoder.encode(request.password()));
        }
        userAccountRepository.save(user);
        return toResponse(user);
    }

    @Transactional
    public void delete(Long id, String operatorUsername) {
        UserAccount user = getById(id);
        if (user.getUsername().equals(operatorUsername)) {
            throw new BusinessException(400, "不能删除当前登录账号");
        }
        userAccountRepository.delete(user);
    }

    private UserAccount getById(Long id) {
        return userAccountRepository.findById(id)
                .orElseThrow(() -> new BusinessException(404, "用户不存在"));
    }

    private UserResponse toResponse(UserAccount user) {
        return new UserResponse(
                user.getId(),
                user.getUsername(),
                user.getDisplayName(),
                user.getRole(),
                user.getCreatedAt());
    }
}
