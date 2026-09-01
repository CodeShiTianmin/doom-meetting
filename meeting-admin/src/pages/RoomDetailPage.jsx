import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import {
  Alert, Box, Button, Card, CardContent, Chip, CircularProgress, Divider, FormControlLabel,
  Grid, IconButton, LinearProgress, List, ListItem, ListItemText, Skeleton, Snackbar, Stack,
  Switch, Table, TableBody, TableCell, TableContainer, TableHead, TableRow, TextField, Tooltip,
  Typography,
} from '@mui/material'
import ArrowBackIcon from '@mui/icons-material/ArrowBack'
import CloseIcon from '@mui/icons-material/Close'
import RefreshIcon from '@mui/icons-material/Refresh'
import RestartAltIcon from '@mui/icons-material/RestartAlt'
import DeleteOutlineIcon from '@mui/icons-material/DeleteOutline'
import FavoriteIcon from '@mui/icons-material/Favorite'
import SmartphoneIcon from '@mui/icons-material/Smartphone'
import StopScreenShareIcon from '@mui/icons-material/StopScreenShare'
import MicIcon from '@mui/icons-material/Mic'
import MicOffIcon from '@mui/icons-material/MicOff'
import VideocamIcon from '@mui/icons-material/Videocam'
import VideocamOffIcon from '@mui/icons-material/VideocamOff'
import PersonRemoveIcon from '@mui/icons-material/PersonRemove'
import CheckIcon from '@mui/icons-material/Check'
import ContentCopyIcon from '@mui/icons-material/ContentCopy'
import HistoryIcon from '@mui/icons-material/History'
import { QRCodeSVG } from 'qrcode.react'
import {
  approveMember, closeRoom, deleteRoom,
  getAttendance, getRoom, kickMember, listRoomEvents, muteAllMembers,
  muteMember, regenerateInvite, resetRoom, setMemberCamera, stopCast,
  updateRoomSettings,
} from '../api'
import { subscribeRoom } from '../api/ws'
import RoomStatusChip from '../components/RoomStatusChip.jsx'
import RedAlertLight from '../components/RedAlertLight.jsx'
import ConfirmDialog from '../components/ConfirmDialog.jsx'
import EmptyState from '../components/EmptyState.jsx'

const CAST_LABELS = { SCREEN: '屏幕共享', VIDEO: '视频推流', CAMERA: '摄像头推流' }
const EVENT_LABELS = {
  ROOM_CREATED: { label: '创建房间', color: 'default' },
  MEMBER_JOINED: { label: '成员加入', color: 'success' },
  MEMBER_LEFT: { label: '成员离开', color: 'default' },
  ROOM_RUNNING: { label: '会议开始', color: 'primary' },
  ROOM_CLOSED: { label: '会议结束', color: 'default' },
  CAST_STARTED: { label: '开始推流', color: 'info' },
  CAST_STOPPED: { label: '停止推流', color: 'default' },
  LIKE: { label: '点赞', color: 'secondary' },
  COUNTDOWN_REMINDER: { label: '倒计时提醒', color: 'warning' },
  UNDERSTAFFED_ALERT: { label: '红灯预警', color: 'error' },
  UNDERSTAFFED_RECOVERED: { label: '预警解除', color: 'success' },
  RECORDING_DETECTED: { label: '检测到录屏', color: 'error' },
  SETTINGS_CHANGED: { label: '设置变更', color: 'default' },
  ROOM_ACTIVATED: { label: '房间激活', color: 'primary' },
  MEMBER_KICKED: { label: '移出成员', color: 'error' },
  MEMBER_MUTED: { label: '静音变更', color: 'default' },
  MEMBER_CAMERA_CHANGED: { label: '摄像头变更', color: 'default' },
  JOIN_REQUEST: { label: '申请入会', color: 'warning' },
  JOIN_APPROVED: { label: '批准入会', color: 'success' },
  JOIN_REJECTED: { label: '拒绝入会', color: 'error' },
  ROOM_RESET: { label: '房间重置', color: 'warning' },
  CAST_CONTROL: { label: '播放控制', color: 'info' },
}
const CLOSE_REASON_LABELS = { MANUAL: '手动结束', TIMEOUT: '会议时长到期' }
const REFRESH_DEBOUNCE_MS = 400

function formatSeconds(total) {
  if (total == null || total < 0) return '--:--'
  const h = Math.floor(total / 3600)
  const m = Math.floor((total % 3600) / 60)
  const s = Math.floor(total % 60)
  const mm = String(m).padStart(2, '0')
  const ss = String(s).padStart(2, '0')
  return h > 0 ? `${h}:${mm}:${ss}` : `${mm}:${ss}`
}

function formatTime(value, withSeconds = true) {
  if (!value) return ''
  return String(value).replace('T', ' ').slice(0, withSeconds ? 19 : 16)
}

async function copyText(text) {
  if (navigator.clipboard?.writeText) {
    await navigator.clipboard.writeText(text)
    return
  }
  const textarea = document.createElement('textarea')
  textarea.value = text
  textarea.setAttribute('readonly', '')
  textarea.style.position = 'fixed'
  textarea.style.opacity = '0'
  document.body.appendChild(textarea)
  textarea.select()
  document.execCommand('copy')
  document.body.removeChild(textarea)
}

function MetricCard({ label, children }) {
  return (
    <Card sx={{ height: '100%' }}>
      <CardContent>
        <Typography variant="overline" color="text.secondary">{label}</Typography>
        {children}
      </CardContent>
    </Card>
  )
}

function DetailSkeleton() {
  return (
    <Box>
      <Skeleton variant="text" width={280} height={40} sx={{ mb: 2 }} />
      <Grid container spacing={2.5} sx={{ mb: 2.5 }}>
        {[0, 1, 2, 3].map((i) => (
          <Grid item xs={12} sm={6} md={3} key={i}>
            <Skeleton variant="rounded" height={150} />
          </Grid>
        ))}
      </Grid>
      <Grid container spacing={2.5}>
        <Grid item xs={12} md={8}><Skeleton variant="rounded" height={360} /></Grid>
        <Grid item xs={12} md={4}><Skeleton variant="rounded" height={360} /></Grid>
      </Grid>
    </Box>
  )
}

export default function RoomDetailPage() {
  const { id } = useParams()
  const navigate = useNavigate()
  const [room, setRoom] = useState(null)
  const [events, setEvents] = useState([])
  const [loadError, setLoadError] = useState('')
  const [error, setError] = useState('')
  const [toast, setToast] = useState('')
  const [remaining, setRemaining] = useState(null)
  const [attendance, setAttendance] = useState(null)
  const [attendanceLoading, setAttendanceLoading] = useState(false)
  const [busyKey, setBusyKey] = useState('')
  const [settingsDraft, setSettingsDraft] = useState({ durationMinutes: '', maxMembers: '' })
  const [confirm, setConfirm] = useState(null)
  const debounceRef = useRef(null)

  const refresh = useCallback(async () => {
    const [r, e] = await Promise.all([getRoom(id), listRoomEvents(id)])
    setRoom(r)
    setEvents(Array.isArray(e) ? e : [])
    setRemaining(r?.remainingSeconds ?? null)
    setLoadError('')
  }, [id])

  useEffect(() => {
    setRoom(null)
    setAttendance(null)
    refresh().catch((err) => setLoadError(err.message || '加载房间失败'))
  }, [refresh])

  const roomDuration = room?.durationMinutes
  const roomMaxMembers = room?.maxMembers
  useEffect(() => {
    if (roomDuration === undefined) return
    setSettingsDraft({
      durationMinutes: String(roomDuration ?? ''),
      maxMembers: String(roomMaxMembers ?? 2),
    })
  }, [roomDuration, roomMaxMembers])

  useEffect(() => {
    if (!room?.roomCode) return undefined
    const unsubscribe = subscribeRoom(room.roomCode, (event) => {
      if (event?.type === 'ROOM_DELETED') {
        navigate('/rooms', { replace: true })
        return
      }
      clearTimeout(debounceRef.current)
      debounceRef.current = setTimeout(() => refresh().catch(() => {}), REFRESH_DEBOUNCE_MS)
    })
    return () => {
      clearTimeout(debounceRef.current)
      unsubscribe()
    }
  }, [room?.roomCode, refresh, navigate])

  // 会议倒计时(本地每秒递减, 与后端 remainingSeconds 校准)
  useEffect(() => {
    if (room?.status !== 'RUNNING') return undefined
    const timer = setInterval(() => {
      setRemaining((prev) => (prev != null && prev > 0 ? prev - 1 : prev))
    }, 1000)
    return () => clearInterval(timer)
  }, [room?.status])

  const progress = useMemo(() => {
    if (!room?.durationMinutes || remaining == null) return 0
    const total = room.durationMinutes * 60
    return Math.min(100, Math.max(0, ((total - remaining) / total) * 100))
  }, [room, remaining])

  const runAction = useCallback(async (key, action, successMessage) => {
    if (busyKey) return
    setBusyKey(key)
    setError('')
    try {
      await action()
      await refresh()
      if (successMessage) setToast(successMessage)
    } catch (err) {
      setError(err.message || '操作失败')
      throw err
    } finally {
      setBusyKey('')
    }
  }, [busyKey, refresh])

  const safeRun = (key, action, successMessage) =>
    runAction(key, action, successMessage).catch(() => {})

  const toggleSetting = (field, value) =>
    safeRun(`setting:${field}`, () => updateRoomSettings(id, { [field]: value }))

  const commitNumericSetting = (field, min, max) => {
    const raw = settingsDraft[field]
    const value = Number(raw)
    if (!Number.isInteger(value) || value < min || value > max) {
      setError(`${field === 'durationMinutes' ? '会议时长' : '成员数上限'}需在 ${min} ~ ${max} 之间`)
      setSettingsDraft((prev) => ({ ...prev, [field]: String(room[field] ?? '') }))
      return
    }
    if (value !== room[field]) toggleSetting(field, value)
  }

  const loadAttendance = async () => {
    setAttendanceLoading(true)
    setError('')
    try {
      const rows = await getAttendance(id)
      setAttendance(Array.isArray(rows) ? rows : [])
    } catch (err) {
      setError(err.message || '加载出席报表失败')
    } finally {
      setAttendanceLoading(false)
    }
  }

  const copyInvite = async (url) => {
    try {
      await copyText(url)
      setToast('邀请链接已复制')
    } catch {
      setError('复制失败, 请手动复制链接')
    }
  }

  if (loadError && !room) {
    return (
      <Box>
        <Button startIcon={<ArrowBackIcon />} onClick={() => navigate('/rooms')} sx={{ mb: 2 }}>返回房间列表</Button>
        <Alert
          severity="error"
          action={<Button color="inherit" size="small" onClick={() => refresh().catch((err) => setLoadError(err.message))}>重试</Button>}
        >
          {loadError}
        </Alert>
      </Box>
    )
  }
  if (!room) return <DetailSkeleton />

  const closed = room.status === 'CLOSED'
  const running = room.status === 'RUNNING'
  const maxMembers = room.maxMembers ?? 2
  const onlineCount = room.onlineMemberCount ?? 0
  const activeMembers = (room.members || []).filter((member) => !member.kicked)
  const pendingCount = activeMembers.filter((member) => member.approved === false).length
  const isSystemRoom = room.createdBy === 'system'
  const invites = (room.invites || []).filter((invite) => !invite.revoked)
  const busy = Boolean(busyKey)

  return (
    <Box>
      <Button
        size="small"
        startIcon={<ArrowBackIcon />}
        onClick={() => navigate('/rooms')}
        sx={{ mb: 1.5, color: 'text.secondary' }}
      >
        房间列表
      </Button>

      <Stack
        direction={{ xs: 'column', md: 'row' }}
        alignItems={{ xs: 'flex-start', md: 'center' }}
        spacing={1.5}
        sx={{ mb: 2.5 }}
      >
        <Stack direction="row" alignItems="center" spacing={1.5} flexWrap="wrap" useFlexGap sx={{ flexGrow: 1, minWidth: 0 }}>
          <RedAlertLight on={room.understaffedAlert} since={room.understaffedSince} />
          <Typography variant="h5" sx={{ wordBreak: 'break-word' }}>{room.name}</Typography>
          <Chip label={`房号 ${room.roomCode}`} sx={{ fontFamily: 'monospace' }} />
          <RoomStatusChip status={room.status} />
          {pendingCount > 0 && <Chip color="warning" size="small" label={`${pendingCount} 人待审批`} />}
        </Stack>
        <Stack direction="row" spacing={1} flexWrap="wrap" useFlexGap>
          <Tooltip title="刷新">
            <IconButton onClick={() => refresh().catch((err) => setError(err.message))} aria-label="刷新">
              <RefreshIcon />
            </IconButton>
          </Tooltip>
          {closed ? (
            <Button
              variant="outlined"
              startIcon={<RestartAltIcon />}
              disabled={busy}
              onClick={() => setConfirm({
                key: 'reset',
                title: '重置房间',
                content: '将清空成员与点赞记录并签发新的入会二维码, 旧凭证全部失效。确定重置?',
                confirmText: '重置',
                confirmColor: 'warning',
                action: () => resetRoom(id),
                success: '房间已重置',
              })}
            >
              重置房间
            </Button>
          ) : (
            <Button
              variant="outlined"
              color="error"
              startIcon={<CloseIcon />}
              disabled={busy}
              onClick={() => setConfirm({
                key: 'close',
                title: '关闭房间',
                content: `关闭后所有成员将被踢出, 入会二维码立即失效。确定关闭“${room.name}”?`,
                confirmText: '关闭房间',
                action: () => closeRoom(id),
                success: '房间已关闭',
              })}
            >
              关闭房间
            </Button>
          )}
          {!isSystemRoom && (
            <Tooltip title="删除房间">
              <IconButton
                color="error"
                disabled={busy}
                aria-label="删除房间"
                onClick={() => setConfirm({
                  key: 'delete',
                  title: '删除房间',
                  content: '删除后房间及其成员、点赞、事件记录将全部移除且不可恢复。确定删除?',
                  confirmText: '永久删除',
                  action: async () => {
                    await deleteRoom(id)
                    navigate('/rooms', { replace: true })
                  },
                  skipRefresh: true,
                })}
              >
                <DeleteOutlineIcon />
              </IconButton>
            </Tooltip>
          )}
        </Stack>
      </Stack>

      {error && <Alert severity="error" sx={{ mb: 2 }} onClose={() => setError('')}>{error}</Alert>}

      {room.understaffedAlert && (
        <Alert severity="error" sx={{ mb: 2 }}>
          红灯预警: 房间人员不足(在线 {onlineCount}/{maxMembers})
          {room.understaffedSince ? `, 自 ${formatTime(room.understaffedSince, false)} 起` : ''}
        </Alert>
      )}
      {closed && room.closeReason && (
        <Alert severity="info" sx={{ mb: 2 }}>
          房间已于 {formatTime(room.closedAt)} 关闭 · {CLOSE_REASON_LABELS[room.closeReason] || room.closeReason}
        </Alert>
      )}

      <Grid container spacing={2.5} sx={{ mb: 2.5 }}>
        <Grid item xs={12} sm={6} md={3}>
          <MetricCard label="会议倒计时">
            <Typography
              variant="h4"
              sx={{ fontVariantNumeric: 'tabular-nums', mb: 1, color: running && remaining != null && remaining <= 300 ? 'error.main' : 'text.primary' }}
            >
              {running ? formatSeconds(remaining) : '--:--'}
            </Typography>
            <LinearProgress
              variant="determinate"
              value={progress}
              color={running && remaining != null && remaining <= 300 ? 'error' : 'primary'}
              sx={{ mb: 1, height: 8, borderRadius: 4 }}
            />
            <Typography variant="caption" color="text.secondary" display="block">
              会议时长 {room.durationMinutes} 分钟 · 到期自动关闭
            </Typography>
            {room.meetingStartAt && (
              <Typography variant="caption" color="text.secondary" display="block">
                开始 {formatTime(room.meetingStartAt)}
              </Typography>
            )}
            {room.meetingEndAt && (
              <Typography variant="caption" color="text.secondary" display="block">
                预计结束 {formatTime(room.meetingEndAt)}
              </Typography>
            )}
            {!room.meetingStartAt && room.scheduledStartAt && (
              <Typography variant="caption" color="text.secondary" display="block">
                预约 {formatTime(room.scheduledStartAt, false)}
              </Typography>
            )}
          </MetricCard>
        </Grid>

        <Grid item xs={12} sm={6} md={3}>
          <MetricCard label="当前推流">
            <Typography variant="h6" noWrap sx={{ mb: 1 }}>
              {room.castType ? (CAST_LABELS[room.castType] || room.castType) : '未推流'}
            </Typography>
            <Stack direction="row" spacing={1} sx={{ mb: 1 }} flexWrap="wrap" useFlexGap>
              {room.castLabel && <Chip size="small" label={room.castLabel} />}
              {room.castBy && <Chip size="small" label={`由 ${room.castBy} 发起`} />}
            </Stack>
            <Button
              size="small"
              variant="outlined"
              color="warning"
              startIcon={busyKey === 'stopCast' ? <CircularProgress size={14} color="inherit" /> : <StopScreenShareIcon />}
              disabled={closed || room.castType == null || busy}
              onClick={() => safeRun('stopCast', () => stopCast(id), '已停止推流')}
              sx={{ mb: 1 }}
            >
              停止推流
            </Button>
            <Typography variant="caption" color="text.secondary" display="block">
              推流由 PC 端发起, 走 LiveKit 实时流
            </Typography>
          </MetricCard>
        </Grid>

        <Grid item xs={12} sm={6} md={3}>
          <MetricCard label="在线成员">
            <Typography variant="h4" sx={{ mb: 1, fontVariantNumeric: 'tabular-nums' }}>
              <SmartphoneIcon sx={{ verticalAlign: 'middle', mr: 1, color: 'primary.main' }} />
              {onlineCount}/{maxMembers}
            </Typography>
            <Chip
              size="small"
              label={room.understaffedAlert ? '缺人预警' : (running ? '成员就位' : '等待加入')}
              color={room.understaffedAlert ? 'error' : (running ? 'success' : 'default')}
            />
          </MetricCard>
        </Grid>

        <Grid item xs={12} sm={6} md={3}>
          <MetricCard label="点赞总数">
            <Typography variant="h4" sx={{ mb: 1, fontVariantNumeric: 'tabular-nums' }}>
              <FavoriteIcon sx={{ verticalAlign: 'middle', mr: 1, color: '#ec407a' }} />
              {room.likeCount ?? 0}
            </Typography>
            <Typography variant="caption" color="text.secondary">
              手机端点赞实时同步并记录
            </Typography>
          </MetricCard>
        </Grid>
      </Grid>

      <Grid container spacing={2.5} alignItems="stretch">
        <Grid item xs={12} md={8} sx={{ display: 'flex', flexDirection: 'column' }}>
          <Card sx={{ mb: 2.5 }}>
            <CardContent>
              <Stack
                direction={{ xs: 'column', sm: 'row' }}
                alignItems={{ xs: 'flex-start', sm: 'center' }}
                spacing={1}
                sx={{ mb: 2 }}
              >
                <Typography variant="h6" sx={{ flexGrow: 1 }}>
                  <SmartphoneIcon sx={{ verticalAlign: 'middle', mr: 1 }} />
                  手机客户端 ({onlineCount}/{maxMembers} 在线)
                </Typography>
                <Stack direction="row" spacing={1}>
                  <Button
                    size="small"
                    variant="outlined"
                    startIcon={room.allMuted ? <MicIcon /> : <MicOffIcon />}
                    disabled={closed || busy}
                    onClick={() => safeRun('muteAll', () => muteAllMembers(id, !room.allMuted))}
                  >
                    {room.allMuted ? '解除全员静音' : '全员静音'}
                  </Button>
                  <Button
                    size="small"
                    variant="outlined"
                    startIcon={attendanceLoading ? <CircularProgress size={14} /> : <HistoryIcon />}
                    disabled={attendanceLoading}
                    onClick={loadAttendance}
                  >
                    出席报表
                  </Button>
                </Stack>
              </Stack>

              {activeMembers.length === 0 ? (
                <EmptyState
                  compact
                  icon={SmartphoneIcon}
                  title={closed ? '房间已关闭' : '等待手机客户扫码加入…'}
                  description={closed ? '重置房间后可再次使用' : '将右侧座位二维码分别发给参会客户'}
                />
              ) : (
                <List dense disablePadding>
                  {activeMembers.map((member) => {
                    const pending = member.approved === false
                    const memberBusy = busyKey.startsWith(`member:${member.identity}`)
                    return (
                      <ListItem
                        key={member.id}
                        disableGutters
                        sx={{
                          px: 1.5, py: 1, mb: 0.75, borderRadius: 2,
                          bgcolor: pending ? 'rgba(251, 140, 0, 0.06)' : 'rgba(79, 70, 229, 0.03)',
                          border: '1px solid',
                          borderColor: pending ? 'rgba(251, 140, 0, 0.3)' : 'rgba(107, 114, 145, 0.12)',
                          '& .MuiListItemSecondaryAction-root': { right: 8 },
                        }}
                        secondaryAction={pending ? (
                          <Stack direction="row" spacing={0.5}>
                            <Tooltip title="批准入会">
                              <IconButton
                                size="small"
                                color="success"
                                disabled={busy}
                                onClick={() => safeRun(`member:${member.identity}:approve`, () => approveMember(id, member.identity, true), `已批准 ${member.nickname} 入会`)}
                              >
                                <CheckIcon fontSize="small" />
                              </IconButton>
                            </Tooltip>
                            <Tooltip title="拒绝入会">
                              <IconButton
                                size="small"
                                color="error"
                                disabled={busy}
                                onClick={() => setConfirm({
                                  key: `member:${member.identity}:reject`,
                                  title: '拒绝入会',
                                  content: `拒绝 ${member.nickname} 的入会申请? 其邀请凭证将失效。`,
                                  confirmText: '拒绝',
                                  action: () => approveMember(id, member.identity, false),
                                })}
                              >
                                <CloseIcon fontSize="small" />
                              </IconButton>
                            </Tooltip>
                          </Stack>
                        ) : (
                          <Stack direction="row" spacing={0.5}>
                            <Tooltip title={member.muted ? '取消静音' : '静音'}>
                              <IconButton
                                size="small"
                                color={member.muted ? 'warning' : 'default'}
                                disabled={closed || busy}
                                onClick={() => safeRun(`member:${member.identity}:mute`, () => muteMember(id, member.identity, !member.muted))}
                              >
                                {member.muted ? <MicOffIcon fontSize="small" /> : <MicIcon fontSize="small" />}
                              </IconButton>
                            </Tooltip>
                            <Tooltip title={member.cameraDisabled ? '允许摄像头' : '禁止摄像头'}>
                              <IconButton
                                size="small"
                                color={member.cameraDisabled ? 'warning' : 'default'}
                                disabled={closed || busy}
                                onClick={() => safeRun(`member:${member.identity}:camera`, () => setMemberCamera(id, member.identity, !member.cameraDisabled))}
                              >
                                {member.cameraDisabled ? <VideocamOffIcon fontSize="small" /> : <VideocamIcon fontSize="small" />}
                              </IconButton>
                            </Tooltip>
                            <Tooltip title="移出会议">
                              <IconButton
                                size="small"
                                color="error"
                                disabled={closed || busy}
                                onClick={() => setConfirm({
                                  key: `member:${member.identity}:kick`,
                                  title: '移出会议',
                                  content: `将 ${member.nickname} 移出会议? 其入会凭证将立即失效, 需重新获取二维码才能加入。`,
                                  confirmText: '移出',
                                  action: () => kickMember(id, member.identity),
                                  success: `已移出 ${member.nickname}`,
                                })}
                              >
                                <PersonRemoveIcon fontSize="small" />
                              </IconButton>
                            </Tooltip>
                          </Stack>
                        )}
                      >
                        <ListItemText
                          sx={{ pr: pending ? 9 : 14 }}
                          primary={(
                            <Stack direction="row" alignItems="center" spacing={1} flexWrap="wrap" useFlexGap>
                              {memberBusy && <CircularProgress size={12} />}
                              <Typography sx={{ fontWeight: 600 }}>
                                {member.seatNo != null ? `${member.seatNo}号 · ` : ''}{member.nickname}
                              </Typography>
                              <Chip
                                size="small"
                                label={pending ? '待审批' : (member.online ? '在线' : '离线')}
                                color={pending ? 'warning' : (member.online ? 'success' : 'default')}
                                variant={member.online || pending ? 'filled' : 'outlined'}
                              />
                              {member.muted && <Chip size="small" variant="outlined" label="已静音" />}
                              {member.cameraDisabled && <Chip size="small" variant="outlined" label="禁摄像头" />}
                            </Stack>
                          )}
                          secondary={[member.deviceInfo, member.joinedAt ? `加入 ${formatTime(member.joinedAt)}` : null]
                            .filter(Boolean).join(' · ')}
                        />
                      </ListItem>
                    )
                  })}
                </List>
              )}

              {attendance && (
                <Box sx={{ mt: 2 }}>
                  <Stack direction="row" alignItems="center" justifyContent="space-between" sx={{ mb: 1 }}>
                    <Typography variant="subtitle2">出席统计报表</Typography>
                    <Button size="small" onClick={() => setAttendance(null)}>收起</Button>
                  </Stack>
                  {attendance.length === 0 ? (
                    <EmptyState compact title="暂无出席记录" />
                  ) : (
                    <TableContainer>
                      <Table size="small" sx={{ minWidth: 520 }}>
                        <TableHead>
                          <TableRow>
                            <TableCell>昵称</TableCell>
                            <TableCell>座位</TableCell>
                            <TableCell>在线时长</TableCell>
                            <TableCell>入会次数</TableCell>
                            <TableCell>点赞</TableCell>
                            <TableCell>状态</TableCell>
                          </TableRow>
                        </TableHead>
                        <TableBody>
                          {attendance.map((row) => (
                            <TableRow key={row.memberId}>
                              <TableCell>{row.nickname}</TableCell>
                              <TableCell>{row.seatNo ?? '-'}</TableCell>
                              <TableCell sx={{ fontVariantNumeric: 'tabular-nums' }}>{formatSeconds(row.onlineSeconds)}</TableCell>
                              <TableCell>{row.joinCount}</TableCell>
                              <TableCell>{row.likeCount}</TableCell>
                              <TableCell>
                                <Chip size="small" label={row.online ? '在线' : '离线'} color={row.online ? 'success' : 'default'} variant={row.online ? 'filled' : 'outlined'} />
                              </TableCell>
                            </TableRow>
                          ))}
                        </TableBody>
                      </Table>
                    </TableContainer>
                  )}
                </Box>
              )}
            </CardContent>
          </Card>

          <Card sx={{ flex: '1 1 0', minHeight: 0, display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
            <CardContent sx={{ flex: 1, minHeight: 0, display: 'flex', flexDirection: 'column' }}>
              <Stack direction="row" alignItems="center" justifyContent="space-between" sx={{ mb: 2 }}>
                <Typography variant="h6">事件日志</Typography>
                <Typography variant="caption" color="text.secondary">最近 {events.length} 条</Typography>
              </Stack>
              {events.length === 0 ? (
                <EmptyState compact icon={HistoryIcon} title="暂无事件" description="成员进出、推流、点赞等操作会记录在此" />
              ) : (
                <TableContainer sx={{ flex: 1, minHeight: 0, maxHeight: 360 }}>
                  <Table size="small" stickyHeader>
                    <TableHead>
                      <TableRow>
                        <TableCell width={120}>类型</TableCell>
                        <TableCell>详情</TableCell>
                        <TableCell width={160}>时间</TableCell>
                      </TableRow>
                    </TableHead>
                    <TableBody>
                      {events.map((event) => {
                        const meta = EVENT_LABELS[event.type] || { label: event.type, color: 'default' }
                        return (
                          <TableRow key={event.id} hover>
                            <TableCell>
                              <Chip size="small" label={meta.label} color={meta.color} variant={meta.color === 'default' ? 'outlined' : 'filled'} />
                            </TableCell>
                            <TableCell sx={{ wordBreak: 'break-word' }}>{event.detail}</TableCell>
                            <TableCell sx={{ whiteSpace: 'nowrap', color: 'text.secondary' }}>{formatTime(event.createdAt)}</TableCell>
                          </TableRow>
                        )
                      })}
                    </TableBody>
                  </Table>
                </TableContainer>
              )}
            </CardContent>
          </Card>
        </Grid>

        <Grid item xs={12} md={4}>
          <Card sx={{ mb: 2.5 }}>
            <CardContent>
              <Typography variant="h6" sx={{ mb: 1 }}>功能设置</Typography>
              <FormControlLabel
                control={(
                  <Switch
                    checked={!!room.videoCallEnabled}
                    disabled={closed || busy}
                    onChange={(e) => toggleSetting('videoCallEnabled', e.target.checked)}
                  />
                )}
                label="手机端视频通话"
              />
              <FormControlLabel
                control={(
                  <Switch
                    checked={!!room.cameraEnabled}
                    disabled={closed || busy || !room.videoCallEnabled}
                    onChange={(e) => toggleSetting('cameraEnabled', e.target.checked)}
                  />
                )}
                label="手机端摄像头"
              />
              <Divider sx={{ my: 1.5 }} />
              <TextField
                fullWidth
                size="small"
                type="number"
                label="会议时长(分钟)"
                inputProps={{ min: 1, max: 720 }}
                value={settingsDraft.durationMinutes}
                disabled={closed || busy}
                onChange={(e) => setSettingsDraft((prev) => ({ ...prev, durationMinutes: e.target.value }))}
                onBlur={() => commitNumericSetting('durationMinutes', 1, 720)}
                onKeyDown={(e) => { if (e.key === 'Enter') e.target.blur() }}
                helperText="失焦后自动保存, 运行中修改会重算结束时间"
              />
              <TextField
                fullWidth
                size="small"
                type="number"
                sx={{ mt: 1.5 }}
                label="成员数上限"
                inputProps={{ min: 1, max: 50 }}
                value={settingsDraft.maxMembers}
                disabled={closed || busy}
                onChange={(e) => setSettingsDraft((prev) => ({ ...prev, maxMembers: e.target.value }))}
                onBlur={() => commitNumericSetting('maxMembers', 1, 50)}
                onKeyDown={(e) => { if (e.key === 'Enter') e.target.blur() }}
                helperText="手机客户端数量, 满员后自动开会"
              />
              <Stack direction="row" spacing={1} sx={{ mt: 1.5 }} flexWrap="wrap" useFlexGap>
                <Chip
                  size="small"
                  color={room.screenshotAllowed === false ? 'error' : 'success'}
                  label={room.screenshotAllowed === false ? '禁止截屏' : '允许截屏'}
                />
                <Chip
                  size="small"
                  color={room.recordingForbidden === false ? 'default' : 'error'}
                  label={room.recordingForbidden === false ? '允许录制' : '禁止录制'}
                />
                {room.approvalRequired && <Chip size="small" color="warning" label="等候室审批" />}
              </Stack>
            </CardContent>
          </Card>

          <Card>
            <CardContent sx={{ textAlign: 'center' }}>
              <Typography variant="h6" sx={{ mb: 2 }}>入会二维码</Typography>
              {closed && (
                <EmptyState compact title="房间已关闭" description="重置房间后将签发新的二维码" />
              )}
              {!closed && invites.length > 0 && (
                <Box>
                  <Grid container spacing={2} justifyContent="center">
                    {invites.map((invite) => (
                      <Grid item xs={12} sm={6} md={12} lg={6} key={invite.token}>
                        <Box
                          sx={{
                            p: 1.5, borderRadius: 3, border: '1px solid',
                            borderColor: invite.used ? 'rgba(107, 114, 145, 0.2)' : 'rgba(79, 70, 229, 0.25)',
                            bgcolor: invite.used ? 'rgba(107, 114, 145, 0.05)' : '#fff',
                            opacity: invite.used ? 0.7 : 1,
                          }}
                        >
                          <Stack direction="row" alignItems="center" justifyContent="center" spacing={1} sx={{ mb: 1 }}>
                            <Typography variant="subtitle2">座位 {invite.seatNo ?? '-'}</Typography>
                            <Chip size="small" label={invite.used ? '已使用' : '待扫码'} color={invite.used ? 'default' : 'primary'} variant="outlined" />
                          </Stack>
                          {invite.inviteUrl && (
                            <Box sx={{ display: 'inline-block', p: 1, bgcolor: '#fff', borderRadius: 2 }}>
                              <QRCodeSVG value={invite.inviteUrl} size={132} />
                            </Box>
                          )}
                          {invite.inviteUrl && (
                            <Stack direction="row" alignItems="center" justifyContent="center" spacing={0.5} sx={{ mt: 0.5 }}>
                              <Typography variant="caption" color="text.secondary" noWrap sx={{ maxWidth: 140 }} title={invite.inviteUrl}>
                                {invite.inviteUrl}
                              </Typography>
                              <Tooltip title="复制链接">
                                <IconButton size="small" onClick={() => copyInvite(invite.inviteUrl)} aria-label="复制邀请链接">
                                  <ContentCopyIcon sx={{ fontSize: 14 }} />
                                </IconButton>
                              </Tooltip>
                            </Stack>
                          )}
                        </Box>
                      </Grid>
                    ))}
                  </Grid>
                  <Typography variant="caption" color="text.secondary" display="block" sx={{ mt: 1.5 }}>
                    每个座位一张二维码, 分别发给不同客户扫码入会
                  </Typography>
                </Box>
              )}
              {!closed && invites.length === 0 && room.qrContent && (
                <Box>
                  <Box sx={{ display: 'inline-block', p: 1.5, bgcolor: '#fff', borderRadius: 3, border: '1px solid rgba(79, 70, 229, 0.25)' }}>
                    <QRCodeSVG value={room.qrContent} size={168} />
                  </Box>
                  {room.inviteUrl && (
                    <Stack direction="row" alignItems="center" justifyContent="center" spacing={0.5} sx={{ mt: 1 }}>
                      <Typography variant="body2" color="text.secondary" noWrap sx={{ maxWidth: 220 }} title={room.inviteUrl}>
                        {room.inviteUrl}
                      </Typography>
                      <Tooltip title="复制链接">
                        <IconButton size="small" onClick={() => copyInvite(room.inviteUrl)} aria-label="复制邀请链接">
                          <ContentCopyIcon sx={{ fontSize: 14 }} />
                        </IconButton>
                      </Tooltip>
                    </Stack>
                  )}
                </Box>
              )}
              {!closed && invites.length === 0 && !room.qrContent && (
                <EmptyState compact title="暂无可用二维码" description="点击下方“重新生成”签发新的入会凭证" />
              )}
              {!closed && room.inviteExpireAt && (
                <Typography variant="caption" color="text.secondary" display="block" sx={{ mt: 1 }}>
                  有效期至 {formatTime(room.inviteExpireAt)}
                </Typography>
              )}
              <Box sx={{ mt: 1.5 }}>
                <Button
                  size="small"
                  startIcon={<RefreshIcon />}
                  disabled={closed || busy}
                  onClick={() => setConfirm({
                    key: 'regenerate',
                    title: '重新生成二维码',
                    content: '重新生成后旧二维码立即失效, 尚未入会的客户需使用新二维码。确定继续?',
                    confirmText: '重新生成',
                    confirmColor: 'primary',
                    action: () => regenerateInvite(id),
                    success: '已生成新的入会二维码',
                  })}
                >
                  重新生成
                </Button>
              </Box>
            </CardContent>
          </Card>
        </Grid>
      </Grid>

      <ConfirmDialog
        open={Boolean(confirm)}
        title={confirm?.title}
        content={confirm?.content}
        confirmText={confirm?.confirmText}
        confirmColor={confirm?.confirmColor || 'error'}
        onClose={() => setConfirm(null)}
        onConfirm={() => {
          if (!confirm) return undefined
          if (confirm.skipRefresh) {
            setError('')
            return confirm.action().catch((err) => {
              setError(err.message || '操作失败')
              throw err
            })
          }
          return runAction(confirm.key, confirm.action, confirm.success)
        }}
      />

      <Snackbar
        open={Boolean(toast)}
        autoHideDuration={2500}
        onClose={() => setToast('')}
        message={toast}
        anchorOrigin={{ vertical: 'bottom', horizontal: 'center' }}
      />
    </Box>
  )
}
