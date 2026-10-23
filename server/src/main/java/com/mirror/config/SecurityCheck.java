package com.mirror.config;

import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Component;

/**
 * 启动自检：默认密码/默认密钥没换就在日志里大声提醒。
 * 交付给别人或在公网跑之前，这几行都应该消失。
 */
@Slf4j
@Component
public class SecurityCheck {

    private static final String DEFAULT_JWT_SECRET = "mirror-dev-secret-please-change-in-production";
    private static final String DEFAULT_AI_TOKEN = "dev-token-change-me";
    private static final String DEFAULT_DB_PASSWORD = "mirror123";

    @Value("${mirror.jwt.secret:}")
    private String jwtSecret;

    @Value("${mirror.ai.token:}")
    private String aiToken;

    @Value("${spring.datasource.password:}")
    private String dbPassword;

    @Value("${springdoc.api-docs.enabled:true}")
    private boolean apiDocsEnabled;

    @EventListener(ApplicationReadyEvent.class)
    public void warnAboutDefaults() {
        int risky = 0;

        if (DEFAULT_JWT_SECRET.equals(jwtSecret)) {
            risky++;
            log.warn("【安全】JWT 密钥还是默认值，任何人都能伪造登录态。"
                    + "请设置环境变量 MIRROR_JWT_SECRET（建议 openssl rand -hex 32）");
        } else if (jwtSecret != null && jwtSecret.length() < 32) {
            risky++;
            log.warn("【安全】JWT 密钥长度只有 {}，建议至少 32 位随机串", jwtSecret.length());
        }

        if (DEFAULT_AI_TOKEN.equals(aiToken)) {
            risky++;
            log.warn("【安全】内部令牌 INTERNAL_TOKEN 还是默认值，本机无所谓，但不要带到公网");
        }

        if (DEFAULT_DB_PASSWORD.equals(dbPassword)) {
            risky++;
            log.warn("【安全】数据库密码还是默认的 mirror123，请用 MIRROR_DB_PASSWORD 覆盖");
        }

        if (apiDocsEnabled) {
            log.info("接口文档已开启：/swagger 。生产环境可设 MIRROR_SWAGGER_ENABLED=false 关闭");
        }

        if (risky == 0) {
            log.info("启动自检通过：密钥与数据库密码都不是默认值");
        } else {
            log.warn("启动自检发现 {} 处默认配置，详见上面几条（本机开发可忽略）", risky);
        }
    }
}
