<template>
  <div class="page" v-loading="loading">
    <template v-if="report">
      <div class="head">
        <h1>面试报告</h1>
        <div>
          <el-button @click="download">导出 Markdown</el-button>
          <el-button link @click="$router.push('/')">再面一场</el-button>
        </div>
      </div>

      <el-row :gutter="16">
        <el-col :xs="24" :sm="9">
          <el-card class="score-card">
            <div class="score">{{ report.total }}</div>
            <div class="unit">/ 5</div>
            <div class="verdict">{{ report.verdict }}</div>
          </el-card>
        </el-col>
        <el-col :xs="24" :sm="15">
          <el-card>
            <div v-if="hasDimensions" ref="chartEl" style="height: 240px"></div>
            <el-empty v-else description="这场没有维度分（可能是评分失败）" :image-size="80" />
          </el-card>
        </el-col>
      </el-row>

      <h2>逐题复盘</h2>
      <el-card v-for="(item, i) in report.items" :key="i" class="q">
        <div class="q-head">
          <span class="q-title">{{ i + 1 }}. {{ item.question }}</span>
          <el-tag :type="tagType(item.score)">{{ item.score }} 分</el-tag>
        </div>
        <p v-if="item.basedOn" class="based">考察依据：{{ item.basedOn }}</p>
        <p class="answer" v-if="item.answer"><b>你的回答：</b>{{ item.answer }}</p>
        <p><b>差距：</b>{{ item.gap }}</p>
        <p v-if="item.betterAnswer"><b>参考讲法：</b>{{ item.betterAnswer }}</p>
      </el-card>

      <h2>下一步</h2>
      <ul class="steps">
        <li v-for="(s, i) in report.nextSteps" :key="i">{{ s }}</li>
      </ul>
    </template>

    <el-empty v-else-if="!loading" description="报告还没生成好" />
  </div>
</template>

<script setup>
import { computed, nextTick, onMounted, ref } from 'vue'
import { useRoute } from 'vue-router'
import { ElMessage } from 'element-plus'
import * as echarts from 'echarts'
import { downloadReport, getReport } from '../api'

const route = useRoute()
const report = ref(null)
const loading = ref(true)
const chartEl = ref(null)

const hasDimensions = computed(() => (report.value?.dimensions?.length || 0) >= 3)

onMounted(async () => {
  try {
    report.value = await getReport(route.params.id)
    await nextTick()
    if (hasDimensions.value) drawChart()
  } catch (e) {
    ElMessage.error(e.message)
  } finally {
    loading.value = false
  }
})

function tagType(score) {
  if (score >= 4) return 'success'
  if (score >= 3) return 'warning'
  return 'danger'
}

function drawChart() {
  const chart = echarts.init(chartEl.value)
  const dims = report.value.dimensions || []

  chart.setOption({
    tooltip: {},
    radar: {
      indicator: dims.map((d) => ({ name: d.name, max: 5 })),
      radius: '65%',
    },
    series: [{
      type: 'radar',
      data: [{
        value: dims.map((d) => d.score),
        name: '本场得分',
        areaStyle: { opacity: 0.2 },
      }],
    }],
  })
  window.addEventListener('resize', () => chart.resize())
}

async function download() {
  try {
    await downloadReport(route.params.id)
  } catch (e) {
    ElMessage.error('导出失败')
  }
}
</script>

<style scoped>
.head { display: flex; justify-content: space-between; align-items: center; flex-wrap: wrap; gap: 8px; }
.score-card { text-align: center; padding: 12px 0; }
.score { font-size: 56px; font-weight: 700; color: #409eff; line-height: 1; }
.unit { color: #bbb; margin-top: 4px; }
.verdict { margin-top: 16px; color: #555; font-size: 14px; }
.q { margin: 12px 0; }
.q-head { display: flex; justify-content: space-between; align-items: flex-start; gap: 12px; }
.q-title { font-weight: 600; }
.based { font-size: 12px; color: #999; margin: 6px 0; }
.answer { color: #666; font-size: 13px; }
.steps { color: #444; line-height: 2; }
</style>
