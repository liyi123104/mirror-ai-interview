# 面镜 · 测试用例

> 本文由 `docs/gen_test_cases.py` 生成，改用例请改脚本后重新生成。配套 Excel：`docs/test-cases.xlsx`（带「实际结果/结论」列，可直接当执行记录用）。

## 测试环境

| 项 | 值 |
|---|---|
| 系统 | Windows 11 / PowerShell 5.1 |
| JDK | 21.0.12（`D:\Jdk\jdk-21.0.12.1`） |
| Maven | 3.9.9 |
| Python | 3.14.8（`ai/.venv`） |
| MySQL | 8.0，库 `mirror`，账号 `mirror/mirror123` |
| 模型 | deepseek-chat；降级 qwen2.5:7b（Ollama） |
| 向量模型 | bge-m3（Ollama），维度 1024 |
| 端口 | AI 8000 / Java 8080 / 前端 5180 |

## 测试数据

| 文件 | 用途 | 对应用例 |
|---|---|---|
| `ai/tests/data/sample-resume.pdf` | 正常电子版中文简历（含手机号/邮箱/技能/项目） | TC-C01、TC-C02、TC-C06 |
| `ai/tests/data/sample-resume-en.pdf` | 全英文、无中文小节标题，用来触发模型兜底 | TC-C08 |
| `ai/tests/data/blank.pdf` | 空白页，没有文字层，模拟扫描件 | TC-C03 |
| `ai/tests/data/fake.docx` | 非 PDF 扩展名 | TC-C04 |
| `ai/data/eval/answers.json` | 10 条带人工分的回答，评分一致性评测 | TC-F07 |
| 一条招聘 JD | 临时文本即可：*熟悉 JVM 内存模型；有高并发与缓存设计经验；了解 Kubernetes 加分* | TC-E02 |

## 优先级定义

| 级别 | 含义 | 处理 |
|---|---|---|
| P0 | 主流程或降级路径，挂了系统就不可用 | 每次改动后必须全过 |
| P1 | 重要功能与关键校验 | 发版前必须全过 |
| P2 | 边界、体验、容错提示 | 有时间就跑 |

## 通过标准

- P0 全过；P1 通过率 ≥ 95%；不允许出现 5000（未预期异常）与前端白屏。
- 业务错误必须带**可读提示**（code≠0 且 message 有内容），不能只返回 500。
- 涉及 AI 的用例，允许回答内容不同，但**结构与状态**必须符合预期。

## 环境启动（9 条）

| 编号 | 用例 | 优先级 | 前置条件 | 操作步骤 | 预期结果 |
|---|---|---|---|---|---|
| TC-A01 | MySQL 服务在线 | P0 | 已安装 MySQL 8，服务名 MySQL80 | 1) 执行 net start MySQL80；2) 执行 netstat -ano \| findstr :3306 | 3306 处于 LISTENING；失败时后端启动会直接报连接失败 |
| TC-A02 | Java 后端健康检查 | P0 | MySQL 在线 | 1) 启动 server（mvn spring-boot:run）；2) GET http://localhost:8080/api/health | 返回 {code:0,data.status:'ok'}，日志出现 Started MirrorApplication |
| TC-A03 | Python AI 健康检查 | P0 | ai/.venv 已装依赖 | 1) 启动 uvicorn（端口 8000）；2) GET http://127.0.0.1:8000/ai/health | 返回 {status:'ok',version:'0.3.0'}；/docs 可打开 |
| TC-A04 | 前端页面可访问 | P0 | web 依赖已安装 | 1) npm run dev -- --port 5180；2) 浏览器打开 http://127.0.0.1:5180 | 出现登录页，控制台无报错 |
| TC-A05 | 前端代理转发正确 | P1 | 前后端都在跑 | 1) GET http://127.0.0.1:5180/api/health | 返回 Java 的 JSON；说明 Vite proxy 指向 8080 |
| TC-A06 | 一键启动脚本 | P1 | 端口 8000/8080/5180 空闲 | 1) 双击 start.bat；2) 等窗口出现三行 [OK] | 三行 [OK] + 「都起来了」汇总；logs/run.json 生成 |
| TC-A07 | 一键关闭脚本 | P1 | 服务由 start.bat 启动 | 1) 双击 stop.bat | 打印「已全部停止」，8000/8080/5180 全部释放；run.json 删除 |
| TC-A08 | 关闭时不误杀其他项目端口 | P2 | 5173 上有别的项目在跑 | 1) 执行 stop.bat | 5173 仍然 listening，只有本项目端口被释放 |
| TC-A09 | 端口被占用时的提示 | P2 | 8000 已被其他程序占用 | 1) 执行 start.bat | 窗口提示端口占用或 [SKIP]，不会静默失败 |

## 认证鉴权（8 条）

| 编号 | 用例 | 优先级 | 前置条件 | 操作步骤 | 预期结果 |
|---|---|---|---|---|---|
| TC-B01 | 注册成功返回 token | P0 | 后端在线，用户名未被占用 | 1) POST /api/auth/register {username:test001,password:test123456} | code=0，data.token 非空，data.username 回显 |
| TC-B02 | 重复用户名注册 | P1 | test001 已注册 | 1) 再次 POST /api/auth/register 同名用户 | code≠0 且提示用户已存在，不返回 token |
| TC-B03 | 密码过短校验 | P1 | 无 | 1) POST /api/auth/register {username:test002,password:123} | 参数校验失败，code=4001，提示 password 不合法 |
| TC-B04 | 登录成功 | P0 | test001 已注册 | 1) POST /api/auth/login 正确账号密码 | code=0，返回新 token |
| TC-B05 | 密码错误登录 | P0 | test001 已注册 | 1) POST /api/auth/login 错误密码 | code≠0，提示用户名或密码错误，不返回 token |
| TC-B06 | 无 token 访问受保护接口 | P0 | 题库接口需鉴权 | 1) GET /api/question?page=1&size=5（不带 Authorization） | code=4010，message=请先登录 |
| TC-B07 | 伪造/过期 token | P1 | 无 | 1) 带 Authorization: Bearer 乱码 请求题库 | code=4010，提示登录已过期 |
| TC-B08 | 越权访问他人面试场次 | P0 | 用户 A 有一场面试，用户 B 已登录 | 1) B 用 A 的 sessionId 调 GET /api/interview/{id}/state | code=4030，message=无权访问这场面试 |

## 简历解析（9 条）

| 编号 | 用例 | 优先级 | 前置条件 | 操作步骤 | 预期结果 |
|---|---|---|---|---|---|
| TC-C01 | 电子版 PDF 抽取手机号/邮箱/技能 | P0 | 准备 ai/tests/data/sample-resume.pdf | 1) 登录后 POST /api/resume/upload 上传该 PDF | code=0；phone=13800138000；email 正确；skills 数量 ≥ 3 |
| TC-C02 | 学历与项目由模型补全 | P0 | 同上，且 DeepSeek 可用 | 1) 上传 sample-resume.pdf；2) 查看 parsed.education 与 parsed.projects | education 非空；projects 至少 1 个且带 tech 数组；usage.tokensIn>0 |
| TC-C03 | 无文字层（扫描件）拦截 | P0 | 准备 ai/tests/data/blank.pdf | 1) 上传 blank.pdf | HTTP 400 → Java 透传 code=4002，message=这份 PDF 没有文字层… |
| TC-C04 | 非 PDF 扩展名拦截 | P1 | 准备 ai/tests/data/fake.docx | 1) 上传 fake.docx | code=4002，message=只支持 PDF 文件 |
| TC-C05 | 超过 10MB 拦截 | P2 | 准备一个 >10MB 的 .pdf | 1) 上传该文件 | code=4002，message=文件不能超过 10MB |
| TC-C06 | 中文不乱码 | P1 | sample-resume.pdf 含中文 | 1) 上传后查看 parsed.name / education / rawText | 姓名与技能均为正常中文，无 é®²è®² 之类乱码 |
| TC-C07 | 模型不可用时的兜底 | P0 | 把 DEEPSEEK_API_KEY 改错且 OLLAMA_BASE_URL 指向无效地址 | 1) 上传 sample-resume.pdf | code=0 不报错；skills 来自规则抽取；needsReview=true |
| TC-C08 | 格式不标准的英文简历走模型 | P1 | 准备 ai/tests/data/sample-resume-en.pdf | 1) 上传该文件 | skills 与 projects 由模型补出；needsReview=false |
| TC-C09 | 空文件上传 | P2 | 无 | 1) POST /api/resume/upload 不带 file 字段 | code=4002，提示请选择一份 PDF 文件 |

## 题库检索（8 条）

| 编号 | 用例 | 优先级 | 前置条件 | 操作步骤 | 预期结果 |
|---|---|---|---|---|---|
| TC-D01 | 新增题目 | P0 | 已登录 | 1) POST /api/question {job:java,dimension:技术深度,stem:…} | code=0，返回 id；数据库 question 表新增 1 行 |
| TC-D02 | 新增后自动建索引 | P1 | AI 服务在线 | 1) 新增 1 道题；2) GET http://127.0.0.1:8000/ai/question/index/size | size 比新增前 +1 |
| TC-D03 | 分页查询 | P1 | 题库有 ≥ 5 道 java 题 | 1) GET /api/question?job=java&page=1&size=5 | code=0，records 长度 ≤5，total 正确 |
| TC-D04 | 按 id 查详情 | P2 | 已有题目 id | 1) GET /api/question/{id} | 返回该题，stem 与新增时一致 |
| TC-D05 | 删除题目并清索引 | P1 | 已有题目 id 且已建索引 | 1) DELETE /api/question/{id}；2) 再查 index/size 并检索该题干 | 删除成功；索引 size −1；检索结果不含该题 |
| TC-D06 | 语义检索命中正确题目 | P0 | 题库含 Redis 缓存穿透、JVM、K8s 等题 | 1) GET /api/question/search?q=缓存穿透&job=java | 第一条为缓存穿透相关题目，score 明显高于其他题 |
| TC-D07 | 空搜索词校验 | P2 | 已登录 | 1) GET /api/question/search?q= （空） | code≠0，提示搜索词不能为空 |
| TC-D08 | 重启后索引恢复 | P1 | 题库有题 | 1) 停掉 Python 再启动，查 size（应为 0）；2) 重启 Java，再查 size | Java 启动同步后 size 恢复为题目数 |

## 面试状态机（11 条）

| 编号 | 用例 | 优先级 | 前置条件 | 操作步骤 | 预期结果 |
|---|---|---|---|---|---|
| TC-E01 | 开始面试返回首题 | P0 | 已登录，AI 在线 | 1) POST /api/interview/start | code=0；返回 sessionId、type=new_question、stem 非空 |
| TC-E02 | 首题基于简历与岗位要求 | P0 | 传入带项目与 R1 要求的简历/JD | 1) POST /api/interview/start 后观察 stem 与 basedOn | 题干围绕项目或 R1 内容，且不含「假数据」 |
| TC-E03 | 短回答触发追问 | P0 | 面试进行中 | 1) POST /{id}/answer {answer:'我用 Redis 做缓存'} | type=follow_up，追问引用原话（含 Redis 或 缓存） |
| TC-E04 | 追问不跑题（原话校验） | P1 | 同一场面试 | 1) 连续提交两个短回答 | 追问都包含回答里的连续片段，不出现「你能详细说说吗」这类套话 |
| TC-E05 | 连续追问不超过 maxDepth | P1 | 面试进行中，maxDepth=2 | 1) 连续提交 3 次长回答，记录 type 序列 | 连续 follow_up 不超过 2 次，之后出现 new_question |
| TC-E06 | 答满八题自动结束 | P0 | 面试进行中且已答 7 题 | 1) 提交第 8 题回答 | 返回 finished=true；session.status=FINISHED；turnCount=8 |
| TC-E07 | 结束后再答被拒 | P0 | 面试已 FINISHED | 1) 再次 POST /{id}/answer | code=4000，message=这场面试已经结束 |
| TC-E08 | 回答过短拦截 | P1 | 面试进行中 | 1) POST /{id}/answer {answer:'好'} | code=4000，message=回答太短了 |
| TC-E09 | 查询场次状态 | P1 | 面试进行中 | 1) GET /api/interview/{id}/state | 返回 status、turnCount、turns 列表（含 interviewer/candidate 交替） |
| TC-E10 | 未登录的开始面试 | P1 | 无 token | 1) POST /api/interview/start | code=4010 |
| TC-E11 | 不存在的场次 | P2 | 已登录 | 1) GET /api/interview/not-exist/state | code=4000，message=面试不存在 |

## 评分（8 条）

| 编号 | 用例 | 优先级 | 前置条件 | 操作步骤 | 预期结果 |
|---|---|---|---|---|---|
| TC-F01 | 单题四维评分 | P0 | AI 在线 | 1) POST http://127.0.0.1:8000/ai/score {question,answer}（带内部 token） | dimensions 长度=4；每维有 dimension/score/confidence/reason/evidence/raw/diff |
| TC-F02 | 分数范围与整数约束 | P1 | 同上 | 1) 查看各维度 score 与 raw | score ∈ [1,5] 且为整数或 .5；raw 为两次原始整数分 |
| TC-F03 | 证据是回答原文 | P1 | 回答含具体内容 | 1) 查看 evidence 字段并比对回答 | evidence 是回答里的连续片段（去空白后能被回答包含） |
| TC-F04 | 极短回答标记低置信 | P0 | AI 在线 | 1) POST /ai/score {answer:'不知道'} | confidence=low（证据校验失败导致） |
| TC-F05 | 空回答拒绝 | P1 | AI 在线 | 1) POST /ai/score {answer:'  '} | data.error 提示回答是空的，不返回分数 |
| TC-F06 | 不支持的维度 | P2 | AI 在线 | 1) POST /ai/score {dimensions:['随便写的维度']} | data.error 提示不支持的维度 |
| TC-F07 | 同一回答两次打分差值 ≤1 | P0 | 评测集 ai/data/eval/answers.json | 1) python ai/tools/eval_consistency.py | 打印「差值不超过 1 分的比例」，应为 100%（温度 0） |
| TC-F08 | 降级到本地模型 | P2 | DeepSeek key 置空，Ollama 已启动且有 qwen2.5:7b | 1) POST /ai/score | 仍返回结果，耗时变长；Python 日志显示使用 qwen2.5:7b |

## 报告（7 条）

| 编号 | 用例 | 优先级 | 前置条件 | 操作步骤 | 预期结果 |
|---|---|---|---|---|---|
| TC-G01 | 结束后生成报告 | P0 | 面试 FINISHED | 1) GET /api/interview/{id}/report | code=0；total 1–5；verdict 非空；items 长度=题目数 |
| TC-G02 | 逐题 gap 与参考讲法 | P0 | 同上 | 1) 检查每个 item 的 gap / betterAnswer | gap 指向具体缺失知识点（非「继续努力」空话）；betterAnswer 给出要点 |
| TC-G03 | 四维雷达图数据 | P1 | 面试过程中评分成功 | 1) 查看 report.dimensions | 包含 技术深度/逻辑结构/表达清晰/岗位匹配 四个 name 与 score |
| TC-G04 | 报告幂等 | P0 | 报告已生成 | 1) 连续请求两次 /report | 两次 total、items 完全一致；report 表只有一条记录 |
| TC-G05 | Markdown 导出 | P1 | 报告已生成 | 1) GET /api/interview/{id}/report/markdown | Content-Type: text/markdown;charset=utf-8，内容含总分/逐题/下一步 |
| TC-G06 | 未结束就请求报告 | P2 | 面试 ONGOING 且已有题目 | 1) GET /report | 允许生成（按当前题目），或返回明确业务提示，不 500 |
| TC-G07 | 不存在的场次报告 | P2 | 已登录 | 1) GET /api/interview/not-exist/report | code=4000，message=面试不存在 |

## 成本（3 条）

| 编号 | 用例 | 优先级 | 前置条件 | 操作步骤 | 预期结果 |
|---|---|---|---|---|---|
| TC-H01 | 三类成本都有记录 | P1 | 跑完一场面试并生成报告 | 1) select scene,count(*) from cost_log group by scene | question、score、report 三类都有记录 |
| TC-H02 | 成本统计接口 | P1 | cost_log 有数据 | 1) GET /api/interview/stats | 返回 totalCost/totalTokensIn/totalTokensOut/sessions/avgCostPerSession |
| TC-H03 | 单场成本量级合理 | P2 | 四维双评配置 | 1) 跑完一场八题面试，对比 stats 增量 | 单场约 0.1–0.3 元，不出现 0 或数元级异常 |

## 流式前端（7 条）

| 编号 | 用例 | 优先级 | 前置条件 | 操作步骤 | 预期结果 |
|---|---|---|---|---|---|
| TC-I01 | SSE 事件顺序正确 | P0 | 面试进行中，AI 在线 | 1) curl -N POST /api/interview/{id}/stream {answer} | 依次收到 meta → 多个 delta → done（或 finished） |
| TC-I02 | 追问逐字出现 | P1 | 前端面试页，浏览器已登录 | 1) 提交回答后观察气泡 | 文字逐字出现，带闪烁光标；不是一次性蹦出 |
| TC-I03 | 第八题显示查看报告 | P1 | 已答 7 题 | 1) 提交第 8 题 | 出现「面试结束」提示与「查看报告」按钮 |
| TC-I04 | 刷新不掉登录 | P1 | 已登录 | 1) 登录后刷新页面 | 仍停留在首页，不跳回登录页 |
| TC-I05 | 未登录被拦截 | P1 | 清空 localStorage | 1) 直接打开 / | 自动跳转到 /login |
| TC-I06 | 选完文件即解析并显示技能 | P2 | 前端首页，已登录 | 1) 选择 sample-resume.pdf | 提示解析完成，显示姓名、技能标签数量；needsReview 时给出警告 |
| TC-I07 | 移动端不横向滚动 | P2 | 浏览器设备模拟 iPhone | 1) 依次打开 首页 / 面试页 / 报告页 | 无横向滚动条，气泡与雷达图不溢出 |

## 降级容错（4 条）

| 编号 | 用例 | 优先级 | 前置条件 | 操作步骤 | 预期结果 |
|---|---|---|---|---|---|
| TC-J01 | AI 挂掉时立刻返回 5030 | P0 | Java 在线，停掉 Python | 1) POST /api/interview/start | 秒级返回 {code:5030,message:面试服务暂时不可用}，不是卡 90 秒 |
| TC-J02 | AI 恢复后可继续 | P0 | 刚停过 Python | 1) 重新启动 Python，再 POST /api/interview/start | code=0，正常出题 |
| TC-J03 | AI 不可用时已存数据不丢 | P1 | 面试进行中 | 1) 停掉 Python 后提交回答（应 5030）；2) 启动 Python 后 GET /state | 已答内容仍在；turnCount 未被错误递增 |
| TC-J04 | MySQL 不可用时启动失败可诊断 | P2 | 停掉 MySQL | 1) 启动 Java | 启动失败并在日志给出连接错误，不是静默成功 |

## 执行记录（本项目实测）

| 时间 | 覆盖用例 | 结果 | 证据 |
|---|---|---|---|
| 2026-10-23 21:33 | TC-A01/02/03、TC-B01/04/06/08、TC-C01/03/04、TC-E01/03/06/07、TC-G01/04 | 通过 9 条，失败 0 条 | scripts/acceptance.ps1 输出；logs/acceptance.log |
| 2026-10-23 21:33 | TC-J01 | 通过：code=5030 秒级返回 | acceptance.ps1 -DowngradeOnly |
| 2026-10-23 21:2x | TC-F07 | 通过：差值≤1 比例 100%，与人工平均差 0.60 | ai/tools/eval_consistency.py；docs/eval-log.md |
| 2026-10-23 21:0x | TC-D02/D05/D06/D08 | 通过：索引 size 0→4、重启后 Java 同步恢复、检索缓存穿透命中 | mysql cost_log 与 /ai/question/index/size 查询记录 |
| 2026-10-23 21:xx | TC-H01/H02/H03 | 通过：question/score/report 三类成本入库；单场 0.18 元 | cost_log 表查询；docs/eval-log.md 成本段 |
| 2026-10-23 21:33 | TC-I01 | 通过：收到 meta → delta×N → done | logs/sse.out（curl -N 抓到的事件流） |
| 待人工 | TC-I02/I03/I04/I05/I06/I07、TC-A04/A06/A07、TC-B03/B05、TC-C05、TC-E05 | 未执行（需浏览器人工验证） | 按本文步骤在浏览器里点一遍，把结果填到 Excel 的「实际结果」列 |

## 已知不覆盖 / 限制

- **并发与压测**：只验证了单用户顺序流程，没有做 100 并发的压测（见 `docs/self-test.md` 第 17 题）。
- **权限模型**：只有「本人可访问自己的场次」这一条，没有角色/后台管理。
- **浏览器兼容**：只在 Chrome/Edge 内核验证；Safari 未测。
- **容器部署**：Docker 文件齐备，但本机拉不到 Docker Hub，未做容器内回归（见 README「已知局限」）。
