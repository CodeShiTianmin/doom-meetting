import { Client } from '@stomp/stompjs'
import SockJS from 'sockjs-client'

/**
 * 管理端实时通道: 订阅 /topic/admin/dashboard 与各房间 /topic/rooms/{roomCode}
 * 房间运行/红灯预警/点赞/播放状态等事件实时推送
 */
let stompClient = null
const subscriptions = new Map()
const pendingSubs = []

export function connectWs(onConnect) {
  if (stompClient?.active) {
    onConnect?.()
    return stompClient
  }
  stompClient = new Client({
    webSocketFactory: () => new SockJS('/ws'),
    reconnectDelay: 3000,
    onConnect: () => {
      pendingSubs.splice(0).forEach(({ destination, handler, key }) => {
        doSubscribe(destination, handler, key)
      })
      onConnect?.()
    },
  })
  stompClient.activate()
  return stompClient
}

function doSubscribe(destination, handler, key) {
  const sub = stompClient.subscribe(destination, (message) => {
    try {
      handler(JSON.parse(message.body))
    } catch {
      // 忽略非 JSON 消息
    }
  })
  subscriptions.set(key, sub)
}

export function subscribeTopic(destination, handler) {
  const key = `${destination}:${Math.random().toString(36).slice(2)}`
  if (stompClient?.connected) {
    doSubscribe(destination, handler, key)
  } else {
    pendingSubs.push({ destination, handler, key })
    connectWs()
  }
  return () => {
    const sub = subscriptions.get(key)
    if (sub) {
      sub.unsubscribe()
      subscriptions.delete(key)
    }
  }
}

export function subscribeAdminDashboard(handler) {
  return subscribeTopic('/topic/admin/dashboard', handler)
}

export function subscribeRoom(roomCode, handler) {
  return subscribeTopic(`/topic/rooms/${roomCode}`, handler)
}
