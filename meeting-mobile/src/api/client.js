import axios from 'axios'

// 手机端 API 客户端: 匿名接口, 统一解包 {code,message,data}
const client = axios.create({ baseURL: '/api' })

client.interceptors.response.use(
  (resp) => {
    const body = resp.data
    if (body && typeof body.code === 'number' && body.code !== 0) {
      return Promise.reject(new Error(body.message || '请求失败'))
    }
    return body?.data
  },
  (error) => {
    const message = error.response?.data?.message || error.message || '网络错误'
    return Promise.reject(new Error(message))
  },
)

export const joinRoom = (data) => client.post('/mobile/rooms/join', data)
export const leaveRoom = (roomCode, identity) =>
  client.post(`/mobile/rooms/${roomCode}/leave`, { identity })
export const heartbeat = (roomCode, identity) =>
  client.post(`/mobile/rooms/${roomCode}/heartbeat`, { identity })
export const controlPlayback = (roomCode, data) =>
  client.post(`/mobile/rooms/${roomCode}/playback`, data)
export const sendLike = (roomCode, identity) =>
  client.post(`/mobile/rooms/${roomCode}/like`, { identity })
export const reportRecording = (roomCode, identity, detail) =>
  client.post(`/mobile/rooms/${roomCode}/report-recording`, { identity, detail })
export const getRoomState = (roomCode) => client.get(`/mobile/rooms/${roomCode}/state`)
