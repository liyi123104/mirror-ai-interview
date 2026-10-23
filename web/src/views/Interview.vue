<template>
  <div class="page">
    <div class="header">
      <h2>模拟面试</h2>
      <el-tag type="info">第 {{ turn }} 题 / 共 8 题</el-tag>
    </div>

    <div class="chat">
      <div v-for="(m, i) in messages" :key="i" :class="['bubble', m.role]">
        <div class="content">{{ m.content }}<span v-if="m.typing" class="caret">▌</span></div>
        <div v-if="m.basedOn" class="based">考察依据：{{ m.basedOn }}</div>
      </div>
    </div>

    <div v-if="!finished" class="input-bar">
      <el-input v-model="answer" type="textarea" :rows="4"
                placeholder="说说你的回答，短一点也行（Ctrl+Enter 提交）"
                @keydown.ctrl.enter="submit" />
      <el-button type="primary" :loading="sending" style="width: 100%; margin-top: 8px"
                 @click="submit">
        {{ sending ? '面试官正在思考…' : '提交回答' }}
      </el-button>
    </div>

    <div v-else class="done">
      <el-alert title="面试结束" type="success" :closable="false" />
      <el-button type="primary" size="large" style="margin-top: 16px" @click="toReport">
        查看报告
      </el-button>
    </div>
  </div>
</template>

<script setup>
import { onMounted, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { ElMessage } from 'element-plus'
import { streamAnswer } from '../api'

const route = useRoute()
const router = useRouter()
const sessionId = route.query.id

const messages = ref([])
const answer = ref('')
const sending = ref(false)
const finished = ref(false)
const turn = ref(1)

onMounted(() => {
  if (!sessionId) return router.push('/')
  messages.value.push({
    role: 'interviewer',
    content: route.query.first || '',
    basedOn: route.query.basedOn || '',
  })
})

async function submit() {
  if (!answer.value.trim()) return ElMessage.warning('说点什么吧')
  if (sending.value) return

  const mine = answer.value
  messages.value.push({ role: 'candidate', content: mine })
  answer.value = ''
  sending.value = true

  const bubble = { role: 'interviewer', content: '', basedOn: '', typing: true }
  messages.value.push(bubble)

  try {
    await streamAnswer(sessionId, mine, (evt) => {
      if (evt.type === 'delta') {
        bubble.content += evt.content
      } else if (evt.type === 'done') {
        bubble.typing = false
        bubble.basedOn = evt.basedOn || ''
        turn.value = Math.min(turn.value + 1, 8)
      } else if (evt.type === 'finished') {
        bubble.typing = false
        finished.value = true
      } else if (evt.type === 'error') {
        bubble.typing = false
        ElMessage.error(evt.message)
      }
    })
  } catch (e) {
    bubble.typing = false
    ElMessage.error('网络异常，请重试')
  } finally {
    sending.value = false
  }
}

function toReport() {
  router.push(`/report/${sessionId}`)
}
</script>

<style scoped>
.header { display: flex; justify-content: space-between; align-items: center; }
.chat { margin: 20px 0; min-height: 320px; }
.bubble { margin: 16px 0; max-width: 82%; }
.bubble.interviewer { margin-right: auto; }
.bubble.candidate { margin-left: auto; }
.content {
  display: inline-block;
  padding: 12px 16px;
  border-radius: 10px;
  background: #fff;
  line-height: 1.7;
  text-align: left;
  white-space: pre-wrap;
  word-break: break-word;
}
.bubble.candidate .content { background: #d9ecff; }
.caret { color: #409eff; animation: blink 1s infinite; }
@keyframes blink { 50% { opacity: 0; } }
.based { font-size: 12px; color: #999; margin-top: 4px; }
.input-bar { position: sticky; bottom: 0; background: #f7f8fa; padding: 12px 0; }
.done { text-align: center; padding: 24px; }
</style>
