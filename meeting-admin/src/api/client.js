import axios from 'axios'

// 统一 API 客户端: 自动附带 JWT, 统一处理 {code,message,data} 包装
const client = axios.create({ baseURL: '/api', timeout: 15000 })

client.interceptors.request.use((config) => {
  const token = localStorage.getItem('admin_token')
  if (token) config.headers.Authorization = `Bearer ${token}`
  return config
})

const isLoginRequest = (config) => /\/auth\/login$/.test(config?.url || '')

client.interceptors.response.use(
  (resp) => {
    const body = resp.data
    if (body && typeof body === 'object' && typeof body.code === 'number') {
      if (body.code !== 0) {
        const err = new Error(body.message || '请求失败')
        err.code = body.code
        return Promise.reject(err)
      }
      return body.data
    }
    return body
  },
  (error) => {
    const status = error.response?.status
    const body = error.response?.data
    // 登录接口本身返回 401(密码错误)时不跳转, 交给登录页展示错误
    if (status === 401 && !isLoginRequest(error.config)) {
      localStorage.removeItem('admin_token')
      localStorage.removeItem('admin_username')
      if (window.location.pathname !== '/login') {
        window.location.href = '/login'
      }
    }
    let message = (body && typeof body === 'object' && body.message) || null
    if (!message) {
      if (error.code === 'ECONNABORTED') message = '请求超时, 请稍后重试'
      else if (!error.response) message = '网络连接失败, 请检查服务是否可用'
      else if (status === 403) message = '没有访问权限'
      else if (status >= 500) message = '服务器内部错误'
      else message = error.message || '请求失败'
    }
    const err = new Error(message)
    if (body && typeof body.code === 'number') err.code = body.code
    else if (status) err.code = status
    return Promise.reject(err)
  },
)

export default client
