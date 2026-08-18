import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import {
  Alert, Box, Chip, Dialog, DialogActions, DialogContent, DialogContentText,
  DialogTitle, Button, IconButton, Slide, Slider, Snackbar, Stack, Typography,
} from '@mui/material'
import MicIcon from '@mui/icons-material/Mic'
import MicOffIcon from '@mui/icons-material/MicOff'
import VideocamIcon from '@mui/icons-material/Videocam'
import VideocamOffIcon from '@mui/icons-material/VideocamOff'
import CameraswitchIcon from '@mui/icons-material/Cameraswitch'
import PlayArrowIcon from '@mui/icons-material/PlayArrow'
import PauseIcon from '@mui/icons-material/Pause'
import FavoriteIcon from '@mui/icons-material/Favorite'
import CallEndIcon from '@mui/icons-material/CallEnd'
import Brightness6Icon from '@mui/icons-material/Brightness6'
import VolumeUpIcon from '@mui/icons-material/VolumeUp'
import AccessTimeIcon from '@mui/icons-material/AccessTime'
import HourglassBottomIcon from '@mui/icons-material/HourglassBottom'
import ReportIcon from '@mui/icons-material/Report'
import { Room as LiveKitRoom, RoomEvent, Track } from 'livekit-client'
import {
  controlPlayback, getRoomState, heartbeat, leaveRoom, reportRecording, sendLike,
} from '../api/client'
import { connectRoomWs } from '../api/ws'
import Watermark from '../components/Watermark.jsx'
import FloatingHearts from '../components/FloatingHearts.jsx'
import { installRecordingGuard } from '../utils/recordingGuard.js'

const HEART_COLORS = ['#ff5b7f', '#ff8a65', '#ffd54f', '#7986f5', '#4dd0e1']
const CAST_IDENTITY_PREFIX = 'pc-publisher-'

const formatClock = (seconds) => {
  if (seconds == null || Number.isNaN(seconds)) return '--:--'
  const s = Math.max(0, Math.floor(seconds))
  const h = Math.floor(s / 3600)
  const m = Math.floor((s % 3600) / 60)
  const sec = s % 60
  const mm = String(m).padStart(2, '0')
  const ss = String(sec).padStart(2, '0')
  return h > 0 ? `${h}:${mm}:${ss}` : `${mm}:${ss}`
}

/**
 * 会议房间页(手机客户端):
 * - 主画面: PC 隐藏推流端投放的内容(大窗)
 * - 小窗: 对方客户视频(仅当 PC 端开放视频通话/摄像头时)
 * - 播放控制: 开始播放/暂停/拖拉进度条(两端同步, 指令带序号防冲突)
 * - 明暗/音量: 手机本地调节, 不影响另一客户端
 * - 会议时间: 已进行时长 + 剩余倒计时, 到期房间自动关闭
 * - 点赞: 实时连接 PC 端并记录; 允许截屏, 禁止录制(检测+遮挡+水印)
 */
export default function RoomPage() {
  const navigate = useNavigate()
  const session = useMemo(() => {
    try {
      return JSON.parse(sessionStorage.getItem('meeting_session') || 'null')
    } catch {
      return null
    }
  }, [])

  const [state, setState] = useState(null)
  const [micOn, setMicOn] = useState(true)
  const [camOn, setCamOn] = useState(false)
  const [facingMode, setFacingMode] = useState('user')
  const [brightness, setBrightness] = useState(100)
  const [volume, setVolume] = useState(80)
  const [elapsed, setElapsed] = useState(null)
  const [remaining, setRemaining] = useState(null)
  const [hearts, setHearts] = useState([])
  const [toast, setToast] = useState(null)
  const [recordingBlocked, setRecordingBlocked] = useState(false)
  const [closedDialog, setClosedDialog] = useState(null)
  const [peerOnline, setPeerOnline] = useState(false)
  const [castOnline, setCastOnline] = useState(false)

  const castVideoRef = useRef(null)
  const peerVideoRef = useRef(null)
  const selfVideoRef = useRef(null)
  const livekitRef = useRef(null)
  const seqRef = useRef(Date.now())
  const heartIdRef = useRef(0)

  const roomCode = session?.roomCode
  const identity = session?.identity

  const pushToast = useCallback((message, severity = 'info') => {
    setToast({ message, severity })
  }, [])

  const spawnHeart = useCallback(() => {
    const id = heartIdRef.current += 1
    setHearts((prev) => [...prev.slice(-30), {
      id,
      offset: (id * 17) % 46,
      color: HEART_COLORS[id % HEART_COLORS.length],
    }])
    setTimeout(() => setHearts((prev) => prev.filter((h) => h.id !== id)), 1900)
  }, [])

  // 未入会直接访问 -> 回到入会页
  useEffect(() => {
    if (!session) navigate('/join', { replace: true })
  }, [session, navigate])

  // 房间状态初始化 + 定时校准
  useEffect(() => {
    if (!roomCode) return undefined
    let alive = true
    const load = async () => {
      try {
        const data = await getRoomState(roomCode)
        if (alive) setState(data)
      } catch {
        // 网络抖动时保持现有状态
      }
    }
    load()
    const timer = setInterval(load, 15000)
    return () => {
      alive = false
      clearInterval(timer)
    }
  }, [roomCode])

  // 心跳保活(后端心跳超时判定离线, 触发缺人红灯计时)
  useEffect(() => {
    if (!roomCode || !identity) return undefined
    const timer = setInterval(() => heartbeat(roomCode, identity).catch(() => {}), 10000)
    return () => clearInterval(timer)
  }, [roomCode, identity])

  // 会议时间: 已进行 + 剩余倒计时(本地每秒递推, 与后端校准)
  useEffect(() => {
    if (!state) return undefined
    const timer = setInterval(() => {
      if (state.status === 'RUNNING' && state.meetingStartAt) {
        setElapsed((new Date() - new Date(state.meetingStartAt)) / 1000)
      } else {
        setElapsed(null)
      }
      if (state.status === 'RUNNING' && state.meetingEndAt) {
        setRemaining((new Date(state.meetingEndAt) - new Date()) / 1000)
      } else {
        setRemaining(null)
      }
    }, 1000)
    return () => clearInterval(timer)
  }, [state])

  // 录屏防护: 检测到录制 -> 遮挡画面 + 上报后台
  useEffect(() => {
    if (!roomCode || !identity) return undefined
    return installRecordingGuard((detail) => {
      setRecordingBlocked(true)
      reportRecording(roomCode, identity, detail).catch(() => {})
    })
  }, [roomCode, identity])

  // WS 实时事件: 播放同步/设置变更/倒计时/点赞/房间关闭
  useEffect(() => {
    if (!roomCode) return undefined
    return connectRoomWs(roomCode, (event) => {
      const payload = event.payload || {}
      switch (event.type) {
        case 'PLAYBACK_CONTROL':
          setState((prev) => prev && {
            ...prev,
            playbackState: payload.playbackState ?? prev.playbackState,
            playbackPositionSeconds: payload.positionSeconds ?? prev.playbackPositionSeconds,
          })
          if (payload.identity && payload.identity !== identity) {
            pushToast(`${payload.nickname || '对方'} ${payload.action === 'PLAY' ? '开始播放'
              : payload.action === 'PAUSE' ? '暂停了播放' : '调整了进度'}`)
          }
          break
        case 'SETTINGS_CHANGED':
          setState((prev) => prev && {
            ...prev,
            videoCallEnabled: payload.videoCallEnabled ?? prev.videoCallEnabled,
            cameraEnabled: payload.cameraEnabled ?? prev.cameraEnabled,
            durationMinutes: payload.durationMinutes ?? prev.durationMinutes,
            meetingEndAt: payload.meetingEndAt && payload.meetingEndAt !== 'null'
              ? payload.meetingEndAt : prev.meetingEndAt,
          })
          pushToast('PC 端更新了房间设置')
          break
        case 'ROOM_RUNNING':
          setState((prev) => prev && {
            ...prev,
            status: 'RUNNING',
            meetingStartAt: payload.meetingStartAt,
            meetingEndAt: payload.meetingEndAt,
          })
          pushToast('两位客户已就位, 会议开始计时', 'success')
          break
        case 'CONTENT_CAST':
          setState((prev) => prev && {
            ...prev,
            contentId: payload.contentId,
            contentName: payload.contentName,
            playbackState: 'IDLE',
            playbackPositionSeconds: 0,
          })
          pushToast(`PC 端投放了新内容: ${payload.contentName}`)
          break
        case 'COUNTDOWN_REMINDER':
          pushToast(`会议剩余不足 ${payload.remainingMinutes} 分钟`, 'warning')
          break
        case 'LIKE':
          setState((prev) => prev && { ...prev, likeCount: payload.likeCount ?? prev.likeCount })
          spawnHeart()
          break
        case 'MEMBER_JOINED':
        case 'MEMBER_LEFT':
          if (payload.identity !== identity) {
            pushToast(`${payload.nickname || '对方客户'} ${event.type === 'MEMBER_JOINED' ? '进入了房间' : '离开了房间'}`)
          }
          break
        case 'ROOM_CLOSED':
          setClosedDialog(payload.reason === 'TIMEOUT'
            ? '会议时长已到, 房间自动关闭' : '公司已结束本场会议')
          break
        default:
          break
      }
    })
  }, [roomCode, identity, pushToast, spawnHeart])

  // LiveKit SFU 入会: 订阅 PC 投放流(大窗) + 对方客户音视频(小窗)
  useEffect(() => {
    if (!session?.livekitToken || !session?.livekitWsUrl) return undefined
    const room = new LiveKitRoom({ adaptiveStream: true, dynacast: true })
    livekitRef.current = room

    const attachTrack = (track, participant) => {
      if (participant.identity.startsWith(CAST_IDENTITY_PREFIX)
        || track.source === Track.Source.ScreenShare) {
        setCastOnline(true)
        if (track.kind === Track.Kind.Video && castVideoRef.current) {
          track.attach(castVideoRef.current)
        }
        if (track.kind === Track.Kind.Audio) {
          const el = track.attach()
          el.volume = volume / 100
          el.dataset.castAudio = 'true'
          document.body.appendChild(el)
        }
      } else {
        setPeerOnline(true)
        if (track.kind === Track.Kind.Video && peerVideoRef.current) {
          track.attach(peerVideoRef.current)
        }
        if (track.kind === Track.Kind.Audio) {
          document.body.appendChild(track.attach())
        }
      }
    }

    room
      .on(RoomEvent.TrackSubscribed, (track, _pub, participant) => attachTrack(track, participant))
      .on(RoomEvent.TrackUnsubscribed, (track, _pub, participant) => {
        track.detach().forEach((el) => el.remove())
        if (participant.identity.startsWith(CAST_IDENTITY_PREFIX)) setCastOnline(false)
        else setPeerOnline(false)
      })
      .on(RoomEvent.ParticipantDisconnected, (participant) => {
        if (participant.identity.startsWith(CAST_IDENTITY_PREFIX)) setCastOnline(false)
        else setPeerOnline(false)
      })
      .on(RoomEvent.LocalTrackPublished, (pub) => {
        if (pub.kind === Track.Kind.Video && selfVideoRef.current) {
          pub.track?.attach(selfVideoRef.current)
        }
      })

    room.connect(session.livekitWsUrl, session.livekitToken)
      .then(() => room.localParticipant.setMicrophoneEnabled(true))
      .catch(() => pushToast('音视频服务连接失败, 请检查网络', 'error'))

    return () => {
      document.querySelectorAll('audio[data-cast-audio]').forEach((el) => el.remove())
      room.disconnect()
      livekitRef.current = null
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [session])

  // 音量: 手机本地调节(仅作用于本机投放伴音), 并上报 PC 端展示
  useEffect(() => {
    document.querySelectorAll('audio[data-cast-audio]').forEach((el) => {
      el.volume = volume / 100
    })
  }, [volume])

  const sendPlayback = useCallback(async (action, extra = {}) => {
    if (!roomCode || !identity) return
    seqRef.current += 1
    try {
      const result = await controlPlayback(roomCode, {
        identity, action, seq: seqRef.current, ...extra,
      })
      setState((prev) => prev && {
        ...prev,
        playbackState: result.playbackState ?? prev.playbackState,
        playbackPositionSeconds: result.positionSeconds ?? prev.playbackPositionSeconds,
      })
      if (result.message) pushToast(result.message, 'warning')
    } catch (err) {
      pushToast(err.message, 'error')
    }
  }, [roomCode, identity, pushToast])

  const toggleMic = async () => {
    const next = !micOn
    setMicOn(next)
    await livekitRef.current?.localParticipant.setMicrophoneEnabled(next).catch(() => {})
  }

  const toggleCam = async () => {
    if (!state?.cameraEnabled || !state?.videoCallEnabled) {
      pushToast('PC 端已关闭本房间的视频通话/摄像头功能', 'warning')
      return
    }
    const next = !camOn
    setCamOn(next)
    await livekitRef.current?.localParticipant
      .setCameraEnabled(next, { facingMode }).catch(() => {})
  }

  const switchCamera = async () => {
    if (!camOn) return
    const next = facingMode === 'user' ? 'environment' : 'user'
    setFacingMode(next)
    const participant = livekitRef.current?.localParticipant
    await participant?.setCameraEnabled(false).catch(() => {})
    await participant?.setCameraEnabled(true, { facingMode: next }).catch(() => {})
  }

  const like = async () => {
    try {
      await sendLike(roomCode, identity)
    } catch (err) {
      pushToast(err.message, 'error')
    }
  }

  const leave = async () => {
    await leaveRoom(roomCode, identity).catch(() => {})
    sessionStorage.removeItem('meeting_session')
    navigate('/join', { replace: true })
  }

  if (!session || !state) {
    return (
      <Box sx={{ minHeight: '100vh', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
        <Typography color="text.secondary">正在进入房间…</Typography>
      </Box>
    )
  }

  const running = state.status === 'RUNNING'
  const contentDuration = state.contentDurationSeconds || 3600
  const playing = state.playbackState === 'PLAYING'
  const camAllowed = state.videoCallEnabled && state.cameraEnabled

  return (
    <Box sx={{ height: '100vh', position: 'relative', overflow: 'hidden', bgcolor: '#05071c' }}>
      {/* 主画面: PC 投放流, 明暗为本地 CSS 滤镜调节 */}
      <Box
        component="video"
        ref={castVideoRef}
        autoPlay
        playsInline
        sx={{
          width: '100%', height: '100%', objectFit: 'contain',
          filter: `brightness(${brightness}%)`,
        }}
      />
      {!castOnline && (
        <Box sx={{
          position: 'absolute', inset: 0, display: 'flex', flexDirection: 'column',
          alignItems: 'center', justifyContent: 'center', gap: 1,
        }}>
          <HourglassBottomIcon sx={{ fontSize: 44, color: 'primary.main' }} />
          <Typography color="text.secondary">
            {state.contentName ? `待投放: ${state.contentName}` : '等待公司投放内容…'}
          </Typography>
          {!running && (
            <Typography variant="caption" color="text.secondary">
              两位客户全部就位后会议开始计时
            </Typography>
          )}
        </Box>
      )}

      {/* 对方客户小窗(仅当 PC 端开放视频通话/摄像头) */}
      <Box
        component="video"
        ref={peerVideoRef}
        autoPlay
        playsInline
        sx={{
          position: 'absolute', top: 74, right: 12, width: 108, height: 148,
          objectFit: 'cover', borderRadius: 3, border: '1px solid rgba(255,255,255,0.25)',
          bgcolor: '#10142e', zIndex: 20,
          display: camAllowed && peerOnline ? 'block' : 'none',
        }}
      />
      {/* 本机摄像头预览小窗 */}
      <Box
        component="video"
        ref={selfVideoRef}
        autoPlay
        playsInline
        muted
        sx={{
          position: 'absolute', top: 74, right: camAllowed && peerOnline ? 128 : 12,
          width: 84, height: 116, objectFit: 'cover', borderRadius: 3,
          border: '1px solid rgba(255,255,255,0.2)', bgcolor: '#10142e', zIndex: 20,
          display: camOn ? 'block' : 'none',
          transform: facingMode === 'user' ? 'scaleX(-1)' : 'none',
        }}
      />

      {/* 顶栏: 房间名 / 会议时间 / 剩余倒计时 / 点赞数 */}
      <Stack
        direction="row"
        alignItems="center"
        spacing={1}
        sx={{
          position: 'absolute', top: 0, left: 0, right: 0, p: 1.5, zIndex: 25,
          background: 'linear-gradient(180deg, rgba(5,7,28,0.85), transparent)',
        }}
      >
        <Chip
          size="small"
          color={running ? 'success' : 'default'}
          label={running ? '会议进行中' : state.status === 'CLOSED' ? '已结束' : '等待就位'}
        />
        <Typography variant="body2" sx={{ fontWeight: 700, flex: 1 }} noWrap>
          {state.name} · {state.roomCode}
        </Typography>
        <Chip
          size="small"
          icon={<AccessTimeIcon />}
          label={formatClock(elapsed)}
          variant="outlined"
        />
        <Chip
          size="small"
          icon={<HourglassBottomIcon />}
          color={remaining != null && remaining <= 300 ? 'warning' : 'default'}
          label={`剩 ${formatClock(remaining)}`}
          variant="outlined"
        />
        <Chip size="small" icon={<FavoriteIcon />} label={state.likeCount ?? 0} variant="outlined" />
      </Stack>

      <FloatingHearts hearts={hearts} />

      {/* 底部控制区 */}
      <Box
        sx={{
          position: 'absolute', left: 0, right: 0, bottom: 0, zIndex: 25, p: 1.5, pb: 2.5,
          background: 'linear-gradient(0deg, rgba(5,7,28,0.92), transparent)',
        }}
      >
        {/* 播放控制: 开始/暂停 + 进度条(两端同步) */}
        <Stack direction="row" alignItems="center" spacing={1.5} sx={{ mb: 1 }}>
          <IconButton
            color="primary"
            disabled={!running || !state.contentId}
            onClick={() => sendPlayback(playing ? 'PAUSE' : 'PLAY', {
              positionSeconds: state.playbackPositionSeconds,
            })}
            sx={{ bgcolor: 'rgba(121,134,245,0.18)' }}
          >
            {playing ? <PauseIcon /> : <PlayArrowIcon />}
          </IconButton>
          <Typography variant="caption" sx={{ minWidth: 44 }}>
            {formatClock(state.playbackPositionSeconds)}
          </Typography>
          <Slider
            size="small"
            disabled={!running || !state.contentId}
            value={Math.min(contentDuration, state.playbackPositionSeconds || 0)}
            min={0}
            max={contentDuration}
            onChangeCommitted={(_, value) => sendPlayback('SEEK', {
              positionSeconds: value,
            })}
            sx={{ flex: 1 }}
          />
          <Typography variant="caption" color="text.secondary" noWrap sx={{ maxWidth: 90 }}>
            {state.contentName || '未投放'}
          </Typography>
        </Stack>

        {/* 明暗 / 音量: 本地调节, 不影响另一客户端(上报 PC 端展示) */}
        <Stack direction="row" spacing={2} sx={{ mb: 1.5 }}>
          <Stack direction="row" alignItems="center" spacing={1} sx={{ flex: 1 }}>
            <Brightness6Icon fontSize="small" sx={{ color: 'text.secondary' }} />
            <Slider
              size="small"
              value={brightness}
              min={30}
              max={150}
              onChange={(_, value) => setBrightness(value)}
              onChangeCommitted={(_, value) => sendPlayback('BRIGHTNESS', { value })}
            />
          </Stack>
          <Stack direction="row" alignItems="center" spacing={1} sx={{ flex: 1 }}>
            <VolumeUpIcon fontSize="small" sx={{ color: 'text.secondary' }} />
            <Slider
              size="small"
              value={volume}
              min={0}
              max={100}
              onChange={(_, value) => setVolume(value)}
              onChangeCommitted={(_, value) => sendPlayback('VOLUME', { value })}
            />
          </Stack>
        </Stack>

        {/* 会议工具条: 静音/摄像头/切换/点赞/离会 */}
        <Stack direction="row" justifyContent="space-around">
          <IconButton onClick={toggleMic} sx={{ bgcolor: micOn ? 'rgba(255,255,255,0.08)' : 'rgba(244,67,54,0.25)' }}>
            {micOn ? <MicIcon /> : <MicOffIcon color="error" />}
          </IconButton>
          <IconButton
            onClick={toggleCam}
            sx={{
              bgcolor: camOn ? 'rgba(255,255,255,0.08)' : 'rgba(255,255,255,0.04)',
              opacity: camAllowed ? 1 : 0.4,
            }}
          >
            {camOn ? <VideocamIcon /> : <VideocamOffIcon />}
          </IconButton>
          <IconButton onClick={switchCamera} disabled={!camOn} sx={{ bgcolor: 'rgba(255,255,255,0.08)' }}>
            <CameraswitchIcon />
          </IconButton>
          <IconButton onClick={like} sx={{ bgcolor: 'rgba(255,91,127,0.2)' }}>
            <FavoriteIcon sx={{ color: '#ff5b7f' }} />
          </IconButton>
          <IconButton onClick={leave} sx={{ bgcolor: 'rgba(244,67,54,0.3)' }}>
            <CallEndIcon color="error" />
          </IconButton>
        </Stack>
        <Typography
          variant="caption"
          color="text.secondary"
          sx={{ display: 'block', textAlign: 'center', mt: 1 }}
        >
          允许截屏 · 禁止录制{camAllowed ? '' : ' · 本房间视频通话/摄像头已由公司关闭'}
        </Typography>
      </Box>

      {/* 录屏检测遮挡层 */}
      {recordingBlocked && (
        <Box
          sx={{
            position: 'fixed', inset: 0, zIndex: 1500, bgcolor: '#05071c',
            display: 'flex', flexDirection: 'column', alignItems: 'center',
            justifyContent: 'center', gap: 2, p: 3, textAlign: 'center',
          }}
        >
          <ReportIcon color="error" sx={{ fontSize: 56 }} />
          <Typography variant="h6">检测到录屏行为</Typography>
          <Typography color="text.secondary">
            会议内容禁止录制, 画面已遮挡并上报。停止录制后可继续观看。
          </Typography>
          <Button variant="contained" onClick={() => setRecordingBlocked(false)}>
            我已停止录制
          </Button>
        </Box>
      )}

      <Watermark text={`${session.identity?.slice(-6) || ''} 仅限实时观看`} />

      {/* 房间关闭提示 */}
      <Dialog open={Boolean(closedDialog)} TransitionComponent={Slide}>
        <DialogTitle>会议已结束</DialogTitle>
        <DialogContent>
          <DialogContentText>{closedDialog}</DialogContentText>
        </DialogContent>
        <DialogActions>
          <Button variant="contained" onClick={leave}>返回</Button>
        </DialogActions>
      </Dialog>

      <Snackbar
        open={Boolean(toast)}
        autoHideDuration={2600}
        onClose={() => setToast(null)}
        anchorOrigin={{ vertical: 'top', horizontal: 'center' }}
        sx={{ mt: 5 }}
      >
        <Alert severity={toast?.severity || 'info'} onClose={() => setToast(null)}>
          {toast?.message}
        </Alert>
      </Snackbar>
    </Box>
  )
}
