package com.mirror.client;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.mirror.common.AiUnavailableException;
import com.mirror.common.BizException;
import com.mirror.config.AiProperties;
import lombok.extern.slf4j.Slf4j;
import org.springframework.core.io.ByteArrayResource;
import org.springframework.http.MediaType;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.stereotype.Component;
import org.springframework.util.LinkedMultiValueMap;
import org.springframework.util.MultiValueMap;
import org.springframework.web.client.HttpClientErrorException;
import org.springframework.web.client.ResourceAccessException;
import org.springframework.web.client.RestClient;
import org.springframework.web.multipart.MultipartFile;

import java.util.Map;
import java.util.UUID;

/**
 * 调 Python AI 服务的唯一出口。
 * 所有降级判断都收在这里：Python 挂了就抛 AiUnavailableException，全局异常处理器转 5030。
 */
@Slf4j
@Component
public class AiClient {

    private final RestClient rest;
    private final ObjectMapper json = new ObjectMapper();

    public AiClient(RestClient.Builder builder, AiProperties props) {
        SimpleClientHttpRequestFactory factory = new SimpleClientHttpRequestFactory();
        factory.setConnectTimeout(3000);
        factory.setReadTimeout(props.getTimeoutMs());

        this.rest = builder
                .baseUrl(props.getBaseUrl())
                .defaultHeader("X-Internal-Token", props.getToken())
                .requestFactory(factory)
                .build();
    }

    /** 统一收口：生成 traceId、发请求、拆包、判错。 */
    private JsonNode post(String path, Object body) {
        String traceId = UUID.randomUUID().toString().substring(0, 8);

        try {
            String raw = rest.post()
                    .uri(path)
                    .header("X-Trace-Id", traceId)
                    .contentType(MediaType.APPLICATION_JSON)
                    .body(body)
                    .retrieve()
                    .body(String.class);

            JsonNode root = json.readTree(raw);
            if (root.path("code").asInt(-1) != 0) {
                throw new BizException(root.path("message").asText("AI 调用失败"));
            }
            return root.path("data");

        } catch (ResourceAccessException e) {
            log.error("[{}] AI 服务无响应 {}", traceId, path);
            throw new AiUnavailableException("AI 服务无响应");
        } catch (HttpClientErrorException e) {
            // 4xx 是 Python 主动拒绝（文件类型不对、内容不合格），这是业务错误，要原样给前端
            throw new BizException(4002, detailOf(e.getResponseBodyAsString()));
        } catch (BizException e) {
            throw e;
        } catch (Exception e) {
            log.error("[{}] AI 调用异常 {}", traceId, path, e);
            throw new AiUnavailableException("AI 调用失败");
        }
    }

    /** FastAPI 的报错体是 {"detail": "..."}，取出来当业务提示。 */
    private String detailOf(String body) {
        try {
            String detail = json.readTree(body).path("detail").asText();
            if (!detail.isBlank()) {
                return detail;
            }
        } catch (Exception ignore) {
            // 不是 JSON 就走兜底文案
        }
        return "AI 服务拒绝了这次请求";
    }

    public JsonNode nextQuestion(Object req) {
        return post("/ai/interview/next", req);
    }

    public JsonNode score(Object req) {
        return post("/ai/score", req);
    }

    public JsonNode reportItem(Object req) {
        return post("/ai/report/item", req);
    }

    public JsonNode parseJd(String text) {
        return post("/ai/jd/parse", Map.of("text", text));
    }

    public JsonNode indexQuestions(Object req) {
        return post("/ai/question/index", req);
    }

    public JsonNode searchQuestions(String query, String job, int topK) {
        return post("/ai/question/search",
                Map.of("query", query, "job", job, "topK", topK));
    }

    /** 删题时把索引也删掉，不然检索还能搜到已经删掉的题。 */
    public void removeQuestionIndex(String id) {
        String traceId = UUID.randomUUID().toString().substring(0, 8);

        try {
            rest.delete()
                    .uri("/ai/question/index/{id}", id)
                    .header("X-Trace-Id", traceId)
                    .retrieve()
                    .body(String.class);
        } catch (ResourceAccessException e) {
            log.error("[{}] AI 服务无响应 /ai/question/index", traceId);
            throw new AiUnavailableException("AI 服务无响应");
        } catch (HttpClientErrorException e) {
            throw new BizException(4002, detailOf(e.getResponseBodyAsString()));
        } catch (Exception e) {
            log.error("[{}] 索引删除异常", traceId, e);
            throw new AiUnavailableException("索引删除失败");
        }
    }

    /** 文件上传要单独写，不能走 post()。 */
    public JsonNode parseResume(MultipartFile file) {
        String traceId = UUID.randomUUID().toString().substring(0, 8);

        try {
            MultiValueMap<String, Object> form = new LinkedMultiValueMap<>();
            form.add("file", new ByteArrayResource(file.getBytes()) {
                @Override
                public String getFilename() {
                    return file.getOriginalFilename();
                }
            });

            String raw = rest.post()
                    .uri("/ai/resume/parse")
                    .header("X-Trace-Id", traceId)
                    .contentType(MediaType.MULTIPART_FORM_DATA)
                    .body(form)
                    .retrieve()
                    .body(String.class);

            JsonNode root = json.readTree(raw);
            if (root.path("code").asInt(-1) != 0) {
                throw new BizException(root.path("message").asText("简历解析失败"));
            }
            return root.path("data");

        } catch (ResourceAccessException e) {
            log.error("[{}] AI 服务无响应 /ai/resume/parse", traceId);
            throw new AiUnavailableException("AI 服务无响应");
        } catch (HttpClientErrorException e) {
            throw new BizException(4002, detailOf(e.getResponseBodyAsString()));
        } catch (BizException e) {
            throw e;
        } catch (Exception e) {
            log.error("[{}] 简历解析异常", traceId, e);
            throw new AiUnavailableException("简历解析失败");
        }
    }
}
