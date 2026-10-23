import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

// 只代理 /api：前端永远不直连 Python
export default defineConfig({
  plugins: [vue()],
  server: {
    proxy: {
      '/api': { target: 'http://localhost:8080', changeOrigin: true },
    },
  },
  // 本地预览打包产物时也要能调后端；线上由 Nginx 反代
  preview: {
    proxy: {
      '/api': { target: 'http://localhost:8080', changeOrigin: true },
    },
  },
})
