# Java 与 Python 内部接口契约 v1.0

## 基础约定

| 项 | 值 |
|---|---|
| Base URL | http://127.0.0.1:8000（生产 http://ai:8000） |
| 鉴权 | 请求头 X-Internal-Token，值与环境变量 INTERNAL_TOKEN 一致 |
| 编码 | UTF-8 |
| 时间单位 | 毫秒 |

## 统一响应

```json
{"code": 0, "message": "ok", "data": {...}}
```

code 非 0 表示业务失败，Java 直接透传给前端。

## 接口一：解析简历

POST /ai/resume/parse，Content-Type: multipart/form-data

| 参数 | 类型 | 说明 |
|---|---|---|
| file | 文件 | PDF |

响应 data：

```json
{
  "name": "张三",
  "phone": "13800138000",
  "email": "zhang@example.com",
  "education": "本科 某某大学",
  "projects": [{"name": "订单系统", "tech": ["Redis"], "desc": "..."}],
  "skills": ["Java", "MySQL"],
  "needsReview": false,
  "usage": {"tokensIn": 0, "tokensOut": 0, "cost": 0.0}
}
```

## 接口二：解析 JD

POST /ai/jd/parse

请求：`{"text": "岗位职责：..."}`

响应 data：

```json
{
  "title": "Java 后端工程师",
  "requirements": [
    {"id": "R1", "text": "熟悉 JVM 内存模型", "type": "must"},
    {"id": "R2", "text": "有高并发经验", "type": "nice"}
  ]
}
```

## 接口三：题库索引

POST /ai/question/index

请求：

```json
{"questions": [{"id": "q1", "stem": "题干", "job": "java", "dimension": "技术深度"}]}
```

响应 data：`{"indexed": 1, "failed": 0}`

## 接口四：检索题目

POST /ai/question/search

请求：`{"query": "缓存", "job": "java", "topK": 5}`

响应 data：

```json
{"items": [{"id": "q1", "stem": "...", "score": 0.82}]}
```

## 接口五：下一题

POST /ai/interview/next

请求：

```json
{
  "sessionId": "s001",
  "job": "java",
  "resume": {...},
  "requirements": [...],
  "asked": ["已问过的题干"],
  "lastQuestion": "上一个问题",
  "lastAnswer": "候选人的回答",
  "depth": 1,
  "maxDepth": 2
}
```

响应 data（两种之一）：

```json
{
  "type": "follow_up",
  "stem": "追问内容",
  "basedOn": "",
  "dimension": "技术深度",
  "usage": {"tokensIn": 820, "tokensOut": 42, "cost": 0.0021}
}
```

```json
{
  "type": "new_question",
  "stem": "新题干",
  "basedOn": "R2",
  "dimension": "技术深度",
  "usage": {...}
}
```

## 接口六：评分

POST /ai/score

请求：

```json
{"question": "...", "answer": "...", "dimensions": ["技术深度"]}
```

响应 data：

```json
{
  "dimensions": [
    {
      "dimension": "技术深度",
      "score": 3.0,
      "confidence": "high",
      "reason": "说了用法，没提取舍",
      "evidence": "原样摘录的片段",
      "raw": [3, 3],
      "diff": 0
    }
  ],
  "total": 3.0,
  "usage": {"tokensIn": 640, "tokensOut": 120, "cost": 0.0023}
}
```

## 接口七：生成单题复盘

POST /ai/report/item

请求：`{"question": "...", "basedOn": "...", "answer": "...", "score": 3}`

响应 data：

```json
{
  "gap": "缺了什么",
  "betterAnswer": "更好的讲法",
  "usage": {"tokensIn": 0, "tokensOut": 0, "cost": 0.0}
}
```

## 变更纪律

1. 字段名一律小驼峰
2. 新增字段可以，改名或删除必须双方确认
3. 这份文件只读不改，改动要另起 PR