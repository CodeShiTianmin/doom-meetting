import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// 管理系统构建配置; 开发时将 /api 与 /ws 代理到后端
export default defineConfig({
  plugins: [react()],
  define: {
    global: 'window',
  },
  server: {
    port: 5173,
    proxy: {
      '/api': {
        target: 'http://localhost:8080',
        changeOrigin: true,
      },
      '/ws': {
        target: 'http://localhost:8080',
        changeOrigin: true,
        ws: true,
      },
    },
  },
})
