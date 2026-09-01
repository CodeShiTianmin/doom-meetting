import { Client } from '@stomp/stompjs'
import SockJS from 'sockjs-client'

/**
 * 管理端实时通道: 订阅 /topic/admin/dashboard 与各房间 /topic/rooms/{roomCode}
 * 房间运行/红灯预警/点赞/播放状态等事件实时推送
 */
let stompClient = null
// key -> { destination, handler, sub } (sub 为当前连接上的订阅, 断线后失效)
const subscriptions = new Map()
// 连接状态监听: 'connecting' | 'connected' | 'disconnected'
const statusListeners = new Set()
let status = 'disconnected'

function setStatus(next) {
  if (status === next) return
  status = next
  statusListeners.forEach((listener) => {
    try {
      listener(status)
    } catch {
      // 监听方异常不影响其他监听者
    }
  })
}

export function getWsStatus() {
  return status
}

export function onWsStatusChange(listener) {
  statusListeners.add(listener)
  listener(status)
  return () => statusListeners.delete(listener)
}

export function connectWs(onConnect) {
  if (stompClient?.active) {
    if (stompClient.connected) onConnect?.()
    return stompClient
  }
  setStatus('connecting')
  stompClient = new Client({
    webSocketFactory: () => new SockJS('/ws'),
    reconnectDelay: 3000,
    heartbeatIncoming: 10000,
    heartbeatOutgoing: 10000,
    beforeConnect: () => {
      const token = localStorage.getItem('admin_token')
      stompClient.connectHeaders = token ? { Authorization: `Bearer ${token}` } : {}
      setStatus('connecting')
    },
    onConnect: () => {
      setStatus('connected')
      // 每次连接(含断线重连)都重新建立全部订阅
      subscriptions.forEach((entry, key) => doSubscribe(key))
      onConnect?.()
    },
    onWebSocketClose: () => {
      subscriptions.forEach((entry) => { entry.sub = null })
      setStatus(stompClient?.active ? 'connecting' : 'disconnected')
    },
    onStompError: (frame) => {
      // 服务端拒绝(如 JWT 失效): 记录到控制台, 由重连逻辑用新 token 重试
      console.warn('[ws] STOMP error:', frame.headers?.message || frame.body)
    },
  })
  stompClient.activate()
  return stompClient
}

export async function disconnectWs() {
  subscriptions.clear()
  const client = stompClient
  stompClient = null
  setStatus('disconnected')
  if (client) {
    try {
      await client.deactivate()
    } catch {
      // 忽略关闭过程中的异常
    }
  }
}

function doSubscribe(key) {
  const entry = subscriptions.get(key)
  if (!entry || !stompClient?.connected) return
  if (entry.sub) return
  entry.sub = stompClient.subscribe(entry.destination, (message) => {
    let payload
    try {
      payload = JSON.parse(message.body)
    } catch {
      return // 忽略非 JSON 消息
    }
    try {
      entry.handler(payload)
    } catch (err) {
      console.error('[ws] handler error on', entry.destination, err)
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
      try {
        entry.sub.unsubscribe()
      } catch {
        // 连接已断开时 unsubscribe 可能抛错, 忽略
      }
    }
  }
}

export function subscribeAdminDashboard(handler) {
  return subscribeTopic('/topic/admin/dashboard', handler)
}

export function subscribeRoom(roomCode, handler) {
  return subscribeTopic(`/topic/rooms/${roomCode}`, handler)
}
