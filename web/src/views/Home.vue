<template>
  <div class="page">
    <div class="header">
      <h1>面镜</h1>
      <div>
        <span class="user">{{ username }}</span>
        <el-button link @click="logout">退出</el-button>
      </div>
    </div>

    <el-card class="card">
      <el-upload drag :auto-upload="false" :limit="1" accept=".pdf"
                 :on-change="onFileChange" :on-remove="() => (file = null)">
        <div class="upload-tip">
          把简历 PDF 拖到这里，或点击选择
          <div class="hint">扫描件提取不出文字，请用电子版</div>
        </div>
      </el-upload>

      <el-alert v-if="resume" type="success" :closable="false" class="parsed">
        <template #title>
          已解析：{{ resume.name || '未识别姓名' }} ·
          {{ resume.skills?.length || 0 }} 项技能
          <span v-if="resume.projects?.length"> · {{ resume.projects.length }} 个项目</span>
        </template>
        <div class="skills">
          <el-tag v-for="s in resume.skills" :key="s" size="small" class="skill">{{ s }}</el-tag>
        </div>
      </el-alert>

      <el-form label-width="100px" class="form">
        <el-form-item label="目标岗位">
          <el-select v-model="job" placeholder="请选择">
            <el-option label="Java 后端" value="java" />
            <el-option label="前端" value="frontend" />
            <el-option label="算法" value="algorithm" />
            <el-option label="产品" value="product" />
          </el-select>
        </el-form-item>

        <el-form-item label="JD（可选）">
          <el-input v-model="jd" type="textarea" :rows="5"
                    placeholder="粘贴岗位要求，不填也能开始面试" />
        </el-form-item>
      </el-form>

      <el-button type="primary" size="large" :loading="loading"
                 :disabled="!file" style="width: 100%" @click="start">
        {{ loading ? '正在解析简历并出题…' : '开始面试' }}
      </el-button>
    </el-card>
  </div>
</template>

<script setup>
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import { ElMessage } from 'element-plus'
import { startInterview, uploadResume } from '../api'

const router = useRouter()
const username = localStorage.getItem('username') || ''
const file = ref(null)
const resume = ref(null)
const job = ref('java')
const jd = ref('')
const loading = ref(false)

async function onFileChange(f) {
  file.value = f.raw
  resume.value = null
  // 选完文件立刻解析，用户能先看到抽出来的技能
  if (!f.raw) return
  try {
    const data = await uploadResume(f.raw)
    resume.value = data.parsed
    if (data.parsed.needsReview) {
      ElMessage.warning('部分字段没抽出来，面试题可能不够贴合')
    } else {
      ElMessage.success('简历解析完成')
    }
  } catch (e) {
    ElMessage.error(e.message)
  }
}

function logout() {
  localStorage.clear()
  router.push('/login')
}

async function start() {
  if (!file.value) return ElMessage.warning('请先选择简历')
  if (!resume.value) return ElMessage.warning('简历还没解析好，稍等一下')

  loading.value = true
  try {
    const session = await startInterview({
      job: job.value,
      resumeJson: JSON.stringify(resume.value),
      // 只传一条要求时也带上岗位说明，出题才有依据
      jdJson: JSON.stringify([{ id: 'R1', text: jd.value || `${job.value} 岗位技术能力要求`, type: 'must' }]),
    })

    sessionStorage.setItem('resume', JSON.stringify(resume.value))
    router.push({
      path: '/interview',
      query: {
        id: session.sessionId,
        first: session.stem,
        basedOn: session.basedOn || '',
      },
    })
  } catch (e) {
    ElMessage.error(e.message)
  } finally {
    loading.value = false
  }
}
</script>

<style scoped>
.header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 20px; }
.user { margin-right: 8px; color: #666; font-size: 14px; }
.card { padding: 8px; }
.upload-tip { padding: 32px 0; color: #666; }
.hint { font-size: 12px; color: #aaa; margin-top: 8px; }
.parsed { margin-top: 16px; }
.skills { margin-top: 6px; }
.skill { margin: 0 6px 6px 0; }
.form { margin-top: 20px; }
</style>
