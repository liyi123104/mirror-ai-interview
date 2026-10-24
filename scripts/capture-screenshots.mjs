/**
 * 用本机 Edge 无头模式给三个页面截图（不需要装 Playwright）。
 *
 * 用法：
 *   1) 先确保服务都在跑（双击 start.bat）
 *   2) node scripts/capture-screenshots.mjs
 *
 * 产物：docs/screenshot-login.png / screenshot-interview.png / screenshot-report.png
 *
 * 原理：走 Chrome DevTools Protocol（Node 22+ 自带 WebSocket，所以不装依赖）。
 * 数据：开两场面试——
 *   A 场用模型生成贴合题目的回答，答满八题出报告（给报告页截图用）
 *   B 场保持进行中，在页面上真提交一句，抓“追问逐字出现”那一屏
 */

import { spawn } from 'node:child_process'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const DOCS = path.join(ROOT, 'docs')
const API = 'http://localhost:8080/api'
const WEB = 'http://127.0.0.1:5180'
const EDGE = 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe'
const CDP_PORT = 9222

const log = (...a) => console.log(...a)
const sleep = (ms) => new Promise((r) => setTimeout(r, ms))

// ---------------------------------------------------------------- 模型造回答
function readDeepSeekKey() {
  try {
    const env = fs.readFileSync(path.join(ROOT, 'ai/.env'), 'utf8')
    const m = env.match(/^\s*DEEPSEEK_API_KEY\s*=\s*(.+)$/m)
    return m ? m[1].trim() : ''
  } catch {
    return ''
  }
}

const FALLBACK_ANSWERS = [
  '我用 Redis 做会话缓存，读多写少命中率 95%，并用布隆过滤器挡住不存在的 key',
  '缓存穿透用布隆过滤器加空值缓存，击穿用互斥锁重建热点 key，雪崩给过期时间加随机值',
  '堆线程共享放对象实例，栈线程私有放栈帧和局部变量，方法区存类元信息',
  '对象优先在 Eden 分配，多次 Minor GC 存活后晋升老年代，大对象直接进老年代避免复制',
  '索引失效常见于列上做函数运算、隐式类型转换、前导模糊匹配和不满足最左前缀',
  '用 CompletableFuture 并发把八题复盘一起生成，串行四十秒并发八秒',
  '遇到内存泄漏用 jmap 导堆快照，在 MAT 里定位到 ThreadLocal 没 remove，改成 finally 清理',
  '重做会先把接口契约固定下来再并行开发两侧，减少联调返工',
]

async function synthAnswer(question, key, index) {
  if (!key) return FALLBACK_ANSWERS[index % FALLBACK_ANSWERS.length]
  try {
    const res = await fetch('https://api.deepseek.com/chat/completions', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${key}` },
      body: JSON.stringify({
        model: 'deepseek-chat',
        temperature: 0.7,
        max_tokens: 260,
        messages: [
          {
            role: 'system',
            content: '你在扮演一位有 3 年经验的 Java 后端候选人参加面试。回答要口语化、具体，'
              + '包含实际做法、取舍或踩过的坑，80~150 字，只输出回答本身。',
          },
          { role: 'user', content: question },
        ],
      }),
    })
    if (!res.ok) throw new Error('HTTP ' + res.status)
    const data = await res.json()
    const text = (data.choices?.[0]?.message?.content || '').trim()
    return text.length > 20 ? text : FALLBACK_ANSWERS[index % FALLBACK_ANSWERS.length]
  } catch (e) {
    log(`  [WARN] 模型生成回答失败（${e.message}），用备用答案`)
    return FALLBACK_ANSWERS[index % FALLBACK_ANSWERS.length]
  }
}

// ---------------------------------------------------------------- API
async function api(pathname, { method = 'GET', body, token } = {}) {
  const headers = {}
  if (token) headers.Authorization = `Bearer ${token}`
  let payload
  if (body instanceof FormData) {
    payload = body
  } else if (body !== undefined) {
    headers['Content-Type'] = 'application/json'
    payload = JSON.stringify(body)
  }
  const res = await fetch(API + pathname, { method, headers, body: payload })
  const text = await res.text()
  try {
    return JSON.parse(text)
  } catch {
    throw new Error(`${method} ${pathname} 返回非 JSON：${text.slice(0, 200)}`)
  }
}

async function prepare() {
  const username = 'shot_' + Math.floor(Math.random() * 1e6)
  const reg = await api('/auth/register', { method: 'POST', body: { username, password: 'test123456' } })
  if (reg.code !== 0) throw new Error('注册失败：' + reg.message)
  const token = reg.data.token

  const pdf = fs.readFileSync(path.join(ROOT, 'ai/tests/data/sample-resume.pdf'))
  const form = new FormData()
  form.append('file', new Blob([pdf], { type: 'application/pdf' }), 'sample-resume.pdf')
  const upload = await api('/resume/upload', { method: 'POST', body: form, token })
  if (upload.code !== 0) throw new Error('上传简历失败：' + upload.message)
  const parsed = upload.data.parsed
  log(`  简历解析：${parsed.name} / ${parsed.skills.length} 项技能 / ${parsed.projects.length} 个项目`)

  const jd = [
    { id: 'R1', text: '熟悉 JVM 内存模型与垃圾回收', type: 'must' },
    { id: 'R2', text: '有高并发与缓存设计经验', type: 'must' },
    { id: 'R3', text: '了解 Kubernetes', type: 'nice' },
  ]
  const payload = { job: 'java', resumeJson: JSON.stringify(parsed), jdJson: JSON.stringify(jd) }

  // ---- A 场：真的答完八题，用来出报告
  const a = await api('/interview/start', { method: 'POST', token, body: payload })
  if (a.code !== 0) throw new Error('开始面试失败：' + a.message)
  const sidA = a.data.sessionId
  let question = a.data.stem
  log(`  A 场首题：${question}`)

  const key = readDeepSeekKey()
  for (let i = 0; i < 8; i++) {
    const answer = await synthAnswer(question, key, i)
    const r = await api(`/interview/${sidA}/answer`, { method: 'POST', token, body: { answer } })
    if (r.code !== 0) throw new Error(`第 ${i + 1} 题失败：` + r.message)
    if (r.data.finished) {
      log(`  第 ${i + 1} 题后结束`)
      break
    }
    question = r.data.stem
    log(`  第 ${i + 1} 题 → ${r.data.type}`)
  }

  const report = await api(`/interview/${sidA}/report`, { token })
  if (report.code !== 0) throw new Error('报告失败：' + report.message)
  log(`  报告：总分 ${report.data.total} / 5，${report.data.items.length} 题，维度 ${(report.data.dimensions || []).length} 个`)

  // ---- B 场：保持进行中，给面试页截图用
  const b = await api('/interview/start', { method: 'POST', token, body: payload })
  if (b.code !== 0) throw new Error('开第二场失败：' + b.message)

  return {
    username,
    token,
    reportSid: sidA,
    reportTotal: report.data.total,
    uiSid: b.data.sessionId,
    uiFirst: b.data.stem,
    uiBasedOn: b.data.basedOn || '',
  }
}

// ---------------------------------------------------------------- CDP
class Cdp {
  constructor(ws) {
    this.ws = ws
    this.id = 0
    this.pending = new Map()
    ws.addEventListener('message', (ev) => {
      const msg = JSON.parse(ev.data)
      if (msg.id && this.pending.has(msg.id)) {
        const { resolve, reject } = this.pending.get(msg.id)
        this.pending.delete(msg.id)
        msg.error ? reject(new Error(JSON.stringify(msg.error))) : resolve(msg.result)
      }
    })
  }

  send(method, params = {}) {
    const id = ++this.id
    return new Promise((resolve, reject) => {
      this.pending.set(id, { resolve, reject })
      this.ws.send(JSON.stringify({ id, method, params }))
      setTimeout(() => {
        if (this.pending.has(id)) {
          this.pending.delete(id)
          reject(new Error(`CDP 超时：${method}`))
        }
      }, 90_000)
    })
  }

  async eval(expression) {
    const r = await this.send('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true })
    if (r.exceptionDetails) {
      throw new Error('页面脚本报错：' + (r.exceptionDetails.exception?.description || JSON.stringify(r.exceptionDetails)))
    }
    return r.result?.value
  }

  async waitFor(expression, timeoutMs = 30_000, label = '') {
    const deadline = Date.now() + timeoutMs
    while (Date.now() < deadline) {
      if (await this.eval(expression)) return true
      await sleep(250)
    }
    throw new Error(`等待超时${label ? '：' + label : ''}（${expression}）`)
  }

  async goto(url) {
    await this.send('Page.navigate', { url })
    await this.waitFor('document.readyState === "complete"', 30_000, '页面加载')
    await sleep(900)
  }

  async shot(file) {
    const { data } = await this.send('Page.captureScreenshot', { format: 'png' })
    fs.writeFileSync(file, Buffer.from(data, 'base64'))
    return fs.statSync(file).size
  }
}

async function launchEdge() {
  if (!fs.existsSync(EDGE)) throw new Error('找不到 Edge：' + EDGE)
  const userDataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'mirror-shot-'))
  const child = spawn(EDGE, [
    '--headless=new', '--disable-gpu', '--hide-scrollbars', '--no-first-run',
    '--no-default-browser-check', '--disable-extensions',
    `--remote-debugging-port=${CDP_PORT}`, `--user-data-dir=${userDataDir}`,
    '--window-size=1280,900', 'about:blank',
  ], { stdio: 'ignore' })

  for (let i = 0; i < 60; i++) {
    await sleep(300)
    try {
      const res = await fetch(`http://127.0.0.1:${CDP_PORT}/json/version`)
      if (res.ok) return { child, userDataDir }
    } catch { /* 还没起来 */ }
  }
  throw new Error('Edge 调试端口没起来')
}

async function openTarget() {
  let res = await fetch(`http://127.0.0.1:${CDP_PORT}/json/new?about:blank`, { method: 'PUT' })
  if (!res.ok) res = await fetch(`http://127.0.0.1:${CDP_PORT}/json/new?about:blank`)
  if (res.ok) return res.json()
  const list = await (await fetch(`http://127.0.0.1:${CDP_PORT}/json`)).json()
  const page = list.find((t) => t.type === 'page')
  if (!page) throw new Error('没有可用的标签页')
  return page
}

// ---------------------------------------------------------------- 主流程
async function main() {
  if (!fs.existsSync(DOCS)) fs.mkdirSync(DOCS, { recursive: true })

  log('1/3 造数据：A 场答完八题出报告，B 场留给面试页')
  const ctx = await prepare()

  log('2/3 启动 Edge 无头浏览器')
  const { child, userDataDir } = await launchEdge()
  let code = 0

  try {
    const target = await openTarget()
    const ws = new WebSocket(target.webSocketDebuggerUrl)
    await new Promise((resolve, reject) => {
      ws.addEventListener('open', resolve)
      ws.addEventListener('error', () => reject(new Error('连不上 CDP WebSocket')))
    })
    const cdp = new Cdp(ws)
    await cdp.send('Page.enable')
    await cdp.send('Runtime.enable')
    await cdp.send('Emulation.setDeviceMetricsOverride', {
      width: 1280, height: 900, deviceScaleFactor: 1, mobile: false,
    })

    log('3/3 截图')

    // 登录页
    await cdp.goto(`${WEB}/login`)
    log(`  login     ${((await cdp.shot(path.join(DOCS, 'screenshot-login.png'))) / 1024).toFixed(0)} KB`)

    // 登录态
    await cdp.eval(`localStorage.setItem('token', ${JSON.stringify(ctx.token)});
                    localStorage.setItem('username', ${JSON.stringify(ctx.username)});`)

    // 面试页（B 场，进行中）：真提一句，等追问流式输出完
    const q = new URLSearchParams({ id: ctx.uiSid, first: ctx.uiFirst, basedOn: ctx.uiBasedOn })
    await cdp.goto(`${WEB}/interview?${q.toString()}`)

    const filled = await cdp.eval(`(() => {
      const ta = document.querySelector('textarea');
      if (!ta) return { ok: false, why: 'no textarea' };
      ta.value = '我主要用 Redis 做会话缓存，读多写少，命中率 95%；过期时间加了 5~10 分钟随机值避免雪崩';
      ta.dispatchEvent(new Event('input', { bubbles: true }));
      const btn = [...document.querySelectorAll('button')].find(b => b.textContent.includes('提交回答'));
      if (!btn) return { ok: false, why: 'no submit button' };
      btn.click();
      return { ok: true };
    })()`)
    if (!filled.ok) throw new Error('面试页交互失败：' + JSON.stringify(filled))

    try {
      await cdp.waitFor(`document.querySelectorAll('.bubble').length >= 3`, 60_000, '等追问出现')
      await cdp.waitFor(
        `!![...document.querySelectorAll('button')].find(b => b.textContent.includes('提交回答'))`,
        90_000, '等流式结束',
      )
    } catch (e) {
      const diag = await cdp.eval(`({
        bubbles: document.querySelectorAll('.bubble').length,
        buttons: [...document.querySelectorAll('button')].map(b => b.textContent.trim()).slice(0, 6),
        text: document.body.innerText.slice(0, 300)
      })`)
      log(`  [WARN] ${e.message}`)
      log('  现场：' + JSON.stringify(diag))
      code = 1
    }
    await sleep(700)
    log(`  interview ${((await cdp.shot(path.join(DOCS, 'screenshot-interview.png'))) / 1024).toFixed(0)} KB`)

    // 报告页（A 场）
    await cdp.goto(`${WEB}/report/${ctx.reportSid}`)
    await cdp.waitFor(`!!document.querySelector('canvas')`, 30_000, '等雷达图')
    await sleep(1800)
    log(`  report    ${((await cdp.shot(path.join(DOCS, 'screenshot-report.png'))) / 1024).toFixed(0)} KB`)

    log(code === 0 ? '完成' : '完成（有告警，看图确认）')
  } catch (e) {
    code = 1
    console.error('截图失败：', e.message)
  } finally {
    child.kill()
    await sleep(500)
    try { fs.rmSync(userDataDir, { recursive: true, force: true }) } catch { /* 忽略 */ }
  }
  process.exit(code)
}

main().catch((e) => {
  console.error('脚本失败：', e)
  process.exit(1)
})
