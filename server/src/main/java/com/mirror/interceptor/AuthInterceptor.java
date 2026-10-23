package com.mirror.interceptor;

import com.mirror.common.BizException;
import com.mirror.common.PublicApi;
import com.mirror.util.JwtUtil;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;
import org.springframework.web.method.HandlerMethod;
import org.springframework.web.servlet.HandlerInterceptor;

@Component
@RequiredArgsConstructor
public class AuthInterceptor implements HandlerInterceptor {

    private final JwtUtil jwt;

    @Override
    public boolean preHandle(HttpServletRequest req, HttpServletResponse resp, Object handler) {
        if (!(handler instanceof HandlerMethod hm)) {
            return true;
        }

        // Swagger 和健康检查放行
        String uri = req.getRequestURI();
        if (uri.startsWith("/swagger") || uri.startsWith("/v3/api-docs")
                || uri.startsWith("/api/health")) {
            return true;
        }

        if (hm.hasMethodAnnotation(PublicApi.class)) {
            return true;
        }

        String auth = req.getHeader("Authorization");
        if (auth == null || !auth.startsWith("Bearer ")) {
            throw new BizException(4010, "请先登录");
        }

        try {
            String userId = jwt.parseUserId(auth.substring(7));
            req.setAttribute("userId", userId);
            return true;
        } catch (Exception e) {
            throw new BizException(4010, "登录已过期，请重新登录");
        }
    }
}