package com.mirror.config;

import lombok.Data;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

/**
 * Python AI 服务的连接配置，对应 application.yml 里的 mirror.ai.*
 */
@Data
@Component
@ConfigurationProperties(prefix = "mirror.ai")
public class AiProperties {
    private String baseUrl;
    private String token;
    private int timeoutMs = 90000;
}
