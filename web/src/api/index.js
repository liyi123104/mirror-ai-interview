import axios from 'axios'

const http = axios.create({ baseURL: '/api', timeout: 180000 })

http.interceptors.request.use((cfg) => {
  const token = localStorage.getItem('token')
  if (token) cfg.headers.Authorization = `Bearer ${token}`
  return cfg
})

http.interceptors.response.use(
  (res) => {
    const body = res.data
    if (body.code !== 0) return Promise.reject(new Error(body.message || '请求失败'))
    return body.data
  },
  (err) => {
    if (err.response?.status === 401) {
      localStorage.removeItem('token')
      location.href = '/login'
    }
    return Promise.reject(err)
  }
)

export const register = (username, password) => http.post('/auth/register', { username, password })
export const login = (username, password) => http.post('/auth/login', { username, password })

export const uploadResume = (file) => {
  const form = new FormData()
  form.append('file', file)
  return http.post('/resume/upload', form, {
    headers: { 'Content-Type': 'multipart/form-data' },
  })
}

export const startInterview = (payload) => http.post('/interview/start', payload)
export const getReport = (id) => http.get(`/interview/${id}/report`)
export const getStats = () => http.get('/interview/stats')

/** 报告导出：window.open 带不上 Authorization 头，只能走 axios 拿 blob */
export async function downloadReport(id) {
  const res = await http.get(`/interview/${id}/report/markdown`, { responseType: 'blob' })
  const url = URL.createObjectURL(new Blob([res.data], { type: 'text/markdown;charset=utf-8' }))
  const a = document.createElement('a')
  a.href = url
  a.download = `report-${id}.md`
  a.click()
  URL.revokeObjectURL(url)
}

/** 流式提交回答：fetch 才能读 SSE，axios 不行 */
export async function streamAnswer(sessionId, answer, onEvent) {
  const res = await fetch(`/api/interview/${sessionId}/stream`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${localStorage.getItem('token')}`,
    },
    body: JSON.stringify({ answer }),
  })

  if (!res.ok || !res.body) {
    throw new Error(`流式接口返回 ${res.status}`)
  }

  const reader = res.body.getReader()
  const decoder = new TextDecoder('utf-8')
  let buffer = ''

  while (true) {
    const { done, value } = await reader.read()
    if (done) break

    // stream: true 很重要，否则中文会被按字节切断
    buffer += decoder.decode(value, { stream: true })
    const parts = buffer.split('\n\n')
    buffer = parts.pop()

    for (const part of parts) {
      const line = part.trim()
      if (!line.startsWith('data:')) continue
      const text = line.slice(5).trim()
      if (!text) continue
      try {
        onEvent(JSON.parse(text))
      } catch (e) {
        console.warn('事件解析失败', text)
      }
    }
  }
}
