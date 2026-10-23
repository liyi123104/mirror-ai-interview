package com.mirror.dto;

import jakarta.validation.constraints.NotBlank;

public record StartInterviewRequest(
        @NotBlank(message = "不能为空") String job,
        String resumeJson,
        String jdJson
) {
}