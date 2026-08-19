import axios from 'axios'

// 统一 API 客户端: 自动附带 JWT, 统一处理 {code,message,data} 包装
const client = axios.create({ baseURL: '/api' })

client.interceptors.request.use((config) => {
  const token = localStorage.getItem('admin_token')
  if (token) config.headers.Authorization = `Bearer ${token}`
  return config
})

client.interceptors.response.use(
  (resp) => {
    const body = resp.data
    if (body && typeof body.code === 'number' && body.code !== 0) {
      const err = new Error(body.message || '请求失败')
      err.code = body.code
      return Promise.reject(err)
    }
    return body?.data
  },
  (error) => {
    if (error.response?.status === 401) {
      localStorage.removeItem('admin_token')
      window.location.href = '/login'
    }
    const body = error.response?.data
    const message = body?.message || error.message || '网络错误'
    const err = new Error(message)
    if (typeof body?.code === 'number') err.code = body.code
    return Promise.reject(err)
  },
)

export default client
