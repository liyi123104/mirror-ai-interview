<template>
  <div class="login-page">
    <div class="card">
      <h1>面镜</h1>
      <p class="sub">AI 模拟面试训练</p>

      <el-tabs v-model="tab">
        <el-tab-pane label="登录" name="login">
          <el-input v-model="username" placeholder="用户名" class="mb" />
          <el-input v-model="password" type="password" placeholder="密码" show-password class="mb" />
          <el-button type="primary" :loading="loading" style="width: 100%" @click="doLogin">
            登录
          </el-button>
        </el-tab-pane>

        <el-tab-pane label="注册" name="register">
          <el-input v-model="username" placeholder="用户名（3-32 位）" class="mb" />
          <el-input v-model="password" type="password" placeholder="密码（至少 6 位）" show-password class="mb" />
          <el-button type="primary" :loading="loading" style="width: 100%" @click="doRegister">
            注册并登录
          </el-button>
        </el-tab-pane>
      </el-tabs>
    </div>
  </div>
</template>

<script setup>
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import { ElMessage } from 'element-plus'
import { login, register } from '../api'

const router = useRouter()
const tab = ref('login')
const username = ref('')
const password = ref('')
const loading = ref(false)

function check() {
  if (!username.value || !password.value) {
    ElMessage.warning('请填写用户名和密码')
    return false
  }
  return true
}

function save(data) {
  localStorage.setItem('token', data.token)
  localStorage.setItem('username', data.username)
}

async function doLogin() {
  if (!check()) return
  loading.value = true
  try {
    save(await login(username.value, password.value))
    router.push('/')
  } catch (e) {
    ElMessage.error(e.message)
  } finally {
    loading.value = false
  }
}

async function doRegister() {
  if (!check()) return
  loading.value = true
  try {
    save(await register(username.value, password.value))
    ElMessage.success('注册成功')
    router.push('/')
  } catch (e) {
    ElMessage.error(e.message)
  } finally {
    loading.value = false
  }
}
</script>

<style scoped>
.login-page {
  min-height: 100vh;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 16px;
}
.card {
  width: 360px;
  max-width: 100%;
  background: #fff;
  padding: 32px;
  border-radius: 12px;
  box-shadow: 0 4px 24px rgba(0, 0, 0, 0.06);
}
h1 { margin: 0 0 4px; font-size: 28px; text-align: center; }
.sub { margin: 0 0 24px; text-align: center; color: #888; font-size: 13px; }
.mb { margin-bottom: 12px; }
</style>
