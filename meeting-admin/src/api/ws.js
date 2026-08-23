import { Client } from '@stomp/stompjs'
import SockJS from 'sockjs-client'

/**
 * 管理端实时通道: 订阅 /topic/admin/dashboard 与各房间 /topic/rooms/{roomCode}
 * 房间运行/红灯预警/点赞/播放状态等事件实时推送
 */
let stompClient = null
// key -> { destination, handler, sub } (sub 为当前连接上的订阅, 断线后失效)
const subscriptions = new Map()

export function connectWs(onConnect) {
  if (stompClient?.active) {
    onConnect?.()
    return stompClient
  }
  stompClient = new Client({
    webSocketFactory: () => new SockJS('/ws'),
    reconnectDelay: 3000,
    beforeConnect: () => {
      const token = localStorage.getItem('admin_token')
      stompClient.connectHeaders = token ? { Authorization: `Bearer ${token}` } : {}
    },
    onConnect: () => {
      // 每次连接(含断线重连)都重新建立全部订阅
      subscriptions.forEach((entry, key) => doSubscribe(key))
      onConnect?.()
    },
  })
  stompClient.activate()
  return stompClient
}

function doSubscribe(key) {
  const entry = subscriptions.get(key)
  if (!entry) return
  entry.sub = stompClient.subscribe(entry.destination, (message) => {
    try {
      entry.handler(JSON.parse(message.body))
    } catch {
      // 忽略非 JSON 消息
    }
  })
}

export function subscribeTopic(destination, handler) {
  const key = `${destination}:${Math.random().toString(36).slice(2)}`
  subscriptions.set(key, { destination, handler, sub: null })
  if (stompClient?.connected) {
    doSubscribe(key)
  } else {
    connectWs()
  }
  return () => {
    const entry = subscriptions.get(key)
    subscriptions.delete(key)
    if (entry?.sub && stompClient?.connected) {
      entry.sub.unsubscribe()
    }
  }
}

export function subscribeAdminDashboard(handler) {
  return subscribeTopic('/topic/admin/dashboard', handler)
}

export function subscribeRoom(roomCode, handler) {
  return subscribeTopic(`/topic/rooms/${roomCode}`, handler)
}
