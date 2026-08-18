import { Client } from '@stomp/stompjs'
import SockJS from 'sockjs-client'

/**
 * 手机端实时通道: 订阅 /topic/rooms/{roomCode}
 * 接收播放同步 / 房间设置变更 / 会议倒计时 / 房间关闭等事件
 */
export function connectRoomWs(roomCode, onEvent, onConnect) {
  const client = new Client({
    webSocketFactory: () => new SockJS('/ws'),
    reconnectDelay: 3000,
    onConnect: () => {
      client.subscribe(`/topic/rooms/${roomCode}`, (message) => {
        try {
          onEvent(JSON.parse(message.body))
        } catch {
          // 忽略非 JSON 消息
        }
      })
      onConnect?.()
    },
  })
  client.activate()
  return () => client.deactivate()
}
