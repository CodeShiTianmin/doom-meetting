import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { useParams } from 'react-router-dom'
import {
  Alert, Box, Button, Card, CardContent, Chip, Divider, FormControlLabel,
  Grid, LinearProgress, List, ListItem, ListItemText, Switch, Table,
  TableBody, TableCell, TableHead, TableRow, TextField, Typography,
} from '@mui/material'
import CastIcon from '@mui/icons-material/Cast'
import CloseIcon from '@mui/icons-material/Close'
import RefreshIcon from '@mui/icons-material/Refresh'
import FavoriteIcon from '@mui/icons-material/Favorite'
import SmartphoneIcon from '@mui/icons-material/Smartphone'
import PlayArrowIcon from '@mui/icons-material/PlayArrow'
import PauseIcon from '@mui/icons-material/Pause'
import StopScreenShareIcon from '@mui/icons-material/StopScreenShare'
import { QRCodeSVG } from 'qrcode.react'
import {
  castContent, closeRoom, controlRoomPlayback, getRoom, listRoomEvents,
  regenerateInvite, stopCast, updateRoomSettings, uploadContentFile,
} from '../api'
import { subscribeRoom } from '../api/ws'
import RoomStatusChip from '../components/RoomStatusChip.jsx'
import RedAlertLight from '../components/RedAlertLight.jsx'

function formatSeconds(total) {
  if (total == null || total < 0) return '--:--'
  const h = Math.floor(total / 3600)
  const m = Math.floor((total % 3600) / 60)
  const s = Math.floor(total % 60)
  const mm = String(m).padStart(2, '0')
  const ss = String(s).padStart(2, '0')
  return h > 0 ? `${h}:${mm}:${ss}` : `${mm}:${ss}`
}

export default function RoomDetailPage() {
  const { id } = useParams()
  const [room, setRoom] = useState(null)
  const [events, setEvents] = useState([])
  const [casting, setCasting] = useState(false)
  const [error, setError] = useState('')
  const [remaining, setRemaining] = useState(null)
  const fileInputRef = useRef(null)

  const refresh = useCallback(async () => {
    const [r, e] = await Promise.all([getRoom(id), listRoomEvents(id)])
    setRoom(r)
    setEvents(e)
    setRemaining(r.remainingSeconds)
  }, [id])

  useEffect(() => {
    refresh().catch((err) => setError(err.message))
  }, [refresh])

  useEffect(() => {
    if (!room?.roomCode) return undefined
    const unsubscribe = subscribeRoom(room.roomCode, () => refresh().catch(() => {}))
    return unsubscribe
  }, [room?.roomCode, refresh])

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

  const toggleSetting = async (field, value) => {
    try {
      await updateRoomSettings(id, { [field]: value })
      await refresh()
    } catch (err) {
      setError(err.message)
    }
  }

  const onFileSelected = async (e) => {
    const file = e.target.files?.[0]
    e.target.value = ''
    if (!file) return
    // 投放前冲突检查: 已有投放时提示先停止当前投放
    if (room?.contentId != null) {
      const ok = window.confirm(
        `该房间正在投放「${room.contentName || '当前内容'}」。\n需要先停止当前投放, 才能投放新内容。\n\n确认停止当前投放并投放新文件?`,
      )
      if (!ok) return
    }
    setCasting(true)
    try {
      // 真实文件上传到服务器, 会议结束后自动删除
      const content = await uploadContentFile(file, id)
      await castContent(id, content.id, true)
      await refresh()
    } catch (err) {
      setError(err.code === 409 ? `投放冲突: ${err.message}` : err.message)
    } finally {
      setCasting(false)
    }
  }

  const doStopCast = async () => {
    try {
      await stopCast(id)
      await refresh()
    } catch (err) {
      setError(err.message)
    }
  }

  const doPlayback = async (action, positionSeconds, value) => {
    try {
      await controlRoomPlayback(id, action, positionSeconds, value)
      await refresh()
    } catch (err) {
      setError(err.message)
    }
  }

  const doClose = async () => {
    try {
      await closeRoom(id)
      await refresh()
    } catch (err) {
      setError(err.message)
    }
  }

  const doRegenerate = async () => {
    try {
      await regenerateInvite(id)
      await refresh()
    } catch (err) {
      setError(err.message)
    }
  }

  if (!room) {
    return error
      ? <Alert severity="error">{error}</Alert>
      : <LinearProgress />
  }

  const closed = room.status === 'CLOSED'

  return (
    <Box>
      {error && <Alert severity="error" sx={{ mb: 2 }} onClose={() => setError('')}>{error}</Alert>}
      <Box sx={{ display: 'flex', alignItems: 'center', gap: 2, mb: 3 }}>
        <RedAlertLight on={room.understaffedAlert} />
        <Typography variant="h5">{room.name}</Typography>
        <Chip label={`房号 ${room.roomCode}`} />
        <RoomStatusChip status={room.status} />
        <Box sx={{ flexGrow: 1 }} />
        <input
          ref={fileInputRef}
          type="file"
          hidden
          accept="video/*,audio/*,image/*,.pdf,.ppt,.pptx,.doc,.docx,.xls,.xlsx,.txt,.zip"
          onChange={onFileSelected}
        />
        <Button
          variant="contained"
          startIcon={<CastIcon />}
          onClick={() => fileInputRef.current?.click()}
          disabled={closed || casting}
        >
          {casting ? '投放中…' : '选择文件投放'}
        </Button>
        <Button variant="outlined" color="error" startIcon={<CloseIcon />} onClick={doClose} disabled={closed}>
          关闭房间
        </Button>
      </Box>

      {room.understaffedAlert && (
        <Alert severity="error" sx={{ mb: 2 }}>
          红灯预警: 该房间缺人状态已超过 3 分钟(在线 {room.onlineMemberCount}/{room.maxMembers ?? 2})
        </Alert>
      )}

      {/* 概览指标行 */}
      <Grid container spacing={2.5} sx={{ mb: 2.5 }}>
        <Grid item xs={12} sm={6} md={3}>
          <Card sx={{ height: '100%' }}>
            <CardContent>
              <Typography variant="overline" color="text.secondary">会议倒计时</Typography>
              <Typography variant="h4" sx={{ fontVariantNumeric: 'tabular-nums', mb: 1 }}>
                {room.status === 'RUNNING' ? formatSeconds(remaining) : '--:--'}
              </Typography>
              <LinearProgress variant="determinate" value={progress} sx={{ mb: 1, height: 8, borderRadius: 4 }} />
              <Typography variant="caption" color="text.secondary" display="block">
                会议时长 {room.durationMinutes} 分钟 · 到期自动关闭
              </Typography>
              {room.meetingStartAt && (
                <Typography variant="caption" color="text.secondary" display="block">
                  开始 {room.meetingStartAt.replace('T', ' ')}
                </Typography>
              )}
              {room.meetingEndAt && (
                <Typography variant="caption" color="text.secondary" display="block">
                  预计结束 {room.meetingEndAt.replace('T', ' ')}
                </Typography>
              )}
            </CardContent>
          </Card>
        </Grid>

        <Grid item xs={12} sm={6} md={3}>
          <Card sx={{ height: '100%' }}>
            <CardContent>
              <Typography variant="overline" color="text.secondary">当前投放 / 播放状态</Typography>
              <Typography variant="h6" noWrap sx={{ mb: 1 }}>
                {room.contentName || '未投放'}
              </Typography>
              <Box sx={{ display: 'flex', gap: 1, mb: 1, flexWrap: 'wrap' }}>
                <Chip
                  size="small"
                  label={{ IDLE: '空闲', PLAYING: '播放中', PAUSED: '已暂停' }[room.playbackState] || room.playbackState}
                  color={room.playbackState === 'PLAYING' ? 'success' : 'default'}
                />
                <Chip size="small" label={`进度 ${formatSeconds(room.playbackPositionSeconds)}`} />
              </Box>
              <Box sx={{ display: 'flex', gap: 1, mb: 1, flexWrap: 'wrap' }}>
                <Button
                  size="small"
                  variant="outlined"
                  startIcon={room.playbackState === 'PLAYING' ? <PauseIcon /> : <PlayArrowIcon />}
                  disabled={closed || room.status !== 'RUNNING' || room.contentId == null}
                  onClick={() => doPlayback(room.playbackState === 'PLAYING' ? 'PAUSE' : 'PLAY')}
                >
                  {room.playbackState === 'PLAYING' ? '暂停' : '播放'}
                </Button>
                <Button
                  size="small"
                  variant="outlined"
                  color="warning"
                  startIcon={<StopScreenShareIcon />}
                  disabled={closed || room.contentId == null}
                  onClick={doStopCast}
                >
                  停止投放
                </Button>
              </Box>
              <Typography variant="caption" color="text.secondary">
                可由 PC/管理端与手机端共同控制, 状态实时同步
              </Typography>
            </CardContent>
          </Card>
        </Grid>

        <Grid item xs={12} sm={6} md={3}>
          <Card sx={{ height: '100%' }}>
            <CardContent>
              <Typography variant="overline" color="text.secondary">在线成员</Typography>
              <Typography variant="h4" sx={{ mb: 1 }}>
                <SmartphoneIcon sx={{ verticalAlign: 'middle', mr: 1, color: 'primary.main' }} />
                {room.onlineMemberCount}/{room.maxMembers ?? 2}
              </Typography>
              <Chip
                size="small"
                label={room.understaffedAlert ? '缺人预警' : (room.status === 'RUNNING' ? '成员就位' : '等待加入')}
                color={room.understaffedAlert ? 'error' : (room.status === 'RUNNING' ? 'success' : 'default')}
              />
            </CardContent>
          </Card>
        </Grid>

        <Grid item xs={12} sm={6} md={3}>
          <Card sx={{ height: '100%' }}>
            <CardContent>
              <Typography variant="overline" color="text.secondary">点赞总数</Typography>
              <Typography variant="h4" sx={{ mb: 1 }}>
                <FavoriteIcon sx={{ verticalAlign: 'middle', mr: 1, color: '#ec407a' }} />
                {room.likeCount}
              </Typography>
              <Typography variant="caption" color="text.secondary">
                手机端点赞实时同步并记录
              </Typography>
            </CardContent>
          </Card>
        </Grid>
      </Grid>

      <Grid container spacing={2.5} alignItems="stretch">
        {/* 主区: 成员 + 事件日志 */}
        <Grid item xs={12} md={8} sx={{ display: 'flex', flexDirection: 'column' }}>
          <Card sx={{ mb: 2.5 }}>
            <CardContent>
              <Typography variant="h6" sx={{ mb: 2 }}>
                <SmartphoneIcon sx={{ verticalAlign: 'middle', mr: 1 }} />
                手机客户端({room.onlineMemberCount}/{room.maxMembers ?? 2} 在线)
              </Typography>
              <List dense disablePadding>
                {(room.members || []).map((member) => (
                  <ListItem key={member.id} disableGutters>
                    <ListItemText
                      primary={
                        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                          <Typography>{member.nickname}</Typography>
                          <Chip
                            size="small"
                            label={member.online ? '在线' : '离线'}
                            color={member.online ? 'success' : 'default'}
                          />
                        </Box>
                      }
                      secondary={`${member.deviceInfo || ''} · 加入 ${member.joinedAt?.replace('T', ' ') || ''}`}
                    />
                  </ListItem>
                ))}
                {(room.members || []).length === 0 && (
                  <Typography color="text.secondary">等待手机客户扫码加入…</Typography>
                )}
              </List>
            </CardContent>
          </Card>

          <Card sx={{ flex: '1 1 0', minHeight: 0, display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
            <CardContent sx={{ flex: 1, minHeight: 0, display: 'flex', flexDirection: 'column' }}>
              <Typography variant="h6" sx={{ mb: 2 }}>事件日志</Typography>
              <Box sx={{ flex: 1, minHeight: 0, maxHeight: 360, overflow: 'auto' }}>
              <Table size="small" stickyHeader>
                <TableHead>
                  <TableRow>
                    <TableCell>类型</TableCell>
                    <TableCell>详情</TableCell>
                    <TableCell>时间</TableCell>
                  </TableRow>
                </TableHead>
                <TableBody>
                  {events.map((event) => (
                    <TableRow key={event.id}>
                      <TableCell><Chip size="small" label={event.type} /></TableCell>
                      <TableCell sx={{ wordBreak: 'break-all' }}>{event.detail}</TableCell>
                      <TableCell sx={{ whiteSpace: 'nowrap' }}>{event.createdAt?.replace('T', ' ')}</TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
              </Box>
            </CardContent>
          </Card>
        </Grid>

        {/* 侧栏: 设置 + 二维码 */}
        <Grid item xs={12} md={4}>
          <Card sx={{ mb: 2.5 }}>
            <CardContent>
              <Typography variant="h6" sx={{ mb: 1 }}>功能设置(PC 端控制)</Typography>
              <FormControlLabel
                control={
                  <Switch
                    checked={!!room.videoCallEnabled}
                    disabled={closed}
                    onChange={(e) => toggleSetting('videoCallEnabled', e.target.checked)}
                  />
                }
                label="手机端视频通话"
              />
              <FormControlLabel
                control={
                  <Switch
                    checked={!!room.cameraEnabled}
                    disabled={closed}
                    onChange={(e) => toggleSetting('cameraEnabled', e.target.checked)}
                  />
                }
                label="手机端摄像头"
              />
              <Divider sx={{ my: 1.5 }} />
              <TextField
                fullWidth
                size="small"
                type="number"
                label="会议时长(分钟)"
                defaultValue={room.durationMinutes}
                disabled={closed}
                onBlur={(e) => {
                  const value = Number(e.target.value)
                  if (value && value !== room.durationMinutes) {
                    toggleSetting('durationMinutes', value)
                  }
                }}
              />
              <TextField
                fullWidth
                size="small"
                type="number"
                sx={{ mt: 1.5 }}
                label="成员数上限"
                defaultValue={room.maxMembers ?? 2}
                disabled={closed}
                onBlur={(e) => {
                  const value = Number(e.target.value)
                  if (value && value !== room.maxMembers) {
                    toggleSetting('maxMembers', value)
                  }
                }}
              />
              <Box sx={{ mt: 1.5, display: 'flex', gap: 1, flexWrap: 'wrap' }}>
                <Chip size="small" color="success" label="允许截屏" />
                <Chip size="small" color="error" label="禁止录制" />
              </Box>
            </CardContent>
          </Card>

          <Card>
            <CardContent sx={{ textAlign: 'center' }}>
              <Typography variant="h6" sx={{ mb: 2 }}>入会二维码</Typography>
              {room.qrContent && !closed ? (
                <QRCodeSVG value={room.qrContent} size={168} />
              ) : (
                <Typography color="text.secondary">房间已关闭</Typography>
              )}
              <Typography variant="body2" color="text.secondary" sx={{ mt: 1.5, wordBreak: 'break-all' }}>
                {room.inviteUrl}
              </Typography>
              {room.inviteExpireAt && (
                <Typography variant="caption" color="text.secondary">
                  有效期至 {room.inviteExpireAt.replace('T', ' ')}
                </Typography>
              )}
              <Box sx={{ mt: 1.5 }}>
                <Button size="small" startIcon={<RefreshIcon />} onClick={doRegenerate} disabled={closed}>
                  重新生成
                </Button>
              </Box>
            </CardContent>
          </Card>

        </Grid>
      </Grid>
    </Box>
  )
}
