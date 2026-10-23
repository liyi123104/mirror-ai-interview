package com.mirror.service;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.mirror.common.BizException;
import com.mirror.entity.AppUser;
import com.mirror.mapper.AppUserMapper;
import com.mirror.util.JwtUtil;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

import java.time.LocalDateTime;

@Service
@RequiredArgsConstructor
public class UserService {

    private final AppUserMapper mapper;
    private final JwtUtil jwt;

    public String register(String username, String rawPassword) {
        Long exists = mapper.selectCount(
                new LambdaQueryWrapper<AppUser>().eq(AppUser::getUsername, username));
        if (exists != null && exists > 0) {
            throw new BizException("用户名已存在");
        }

        AppUser u = new AppUser();
        u.setUsername(username);
        u.setPasswordHash(jwt.hash(rawPassword));
        u.setCreatedAt(LocalDateTime.now());
        mapper.insert(u);

        return jwt.create(u.getId(), u.getUsername());
    }

    public String login(String username, String rawPassword) {
        AppUser u = mapper.selectOne(
                new LambdaQueryWrapper<AppUser>().eq(AppUser::getUsername, username));

        if (u == null || !jwt.verify(rawPassword, u.getPasswordHash())) {
            throw new BizException("用户名或密码错误");
        }
        return jwt.create(u.getId(), u.getUsername());
    }
}