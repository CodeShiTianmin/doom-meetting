import { useCallback, useEffect, useMemo, useState } from 'react'
import { useParams } from 'react-router-dom'
import {
  Alert, Box, Button, Card, CardContent, Chip, Dialog, DialogActions,
  DialogContent, DialogTitle, Divider, FormControlLabel, Grid, LinearProgress,
  List, ListItem, ListItemText, MenuItem, Switch, Table, TableBody, TableCell,
  TableHead, TableRow, TextField, Typography,
} from '@mui/material'
import CastIcon from '@mui/icons-material/Cast'
import CloseIcon from '@mui/icons-material/Close'
import RefreshIcon from '@mui/icons-material/Refresh'
import FavoriteIcon from '@mui/icons-material/Favorite'
import SmartphoneIcon from '@mui/icons-material/Smartphone'
import { QRCodeSVG } from 'qrcode.react'
import {
  castContent, closeRoom, getRoom, listContents, listRoomEvents, listRoomLikes,
  regenerateInvite, updateRoomSettings,
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
  const [likes, setLikes] = useState([])
  const [events, setEvents] = useState([])
  const [contents, setContents] = useState([])
  const [castDialog, setCastDialog] = useState(false)
  const [castContentId, setCastContentId] = useState('')
  const [error, setError] = useState('')
  const [remaining, setRemaining] = useState(null)

  const refresh = useCallback(async () => {
    const [r, l, e] = await Promise.all([
      getRoom(id), listRoomLikes(id), listRoomEvents(id),
    ])
    setRoom(r)
    setLikes(l)
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

  const openCast = async () => {
    setCastDialog(true)
    try {
      setContents(await listContents())
    } catch {
      setContents([])
    }
  }

  const doCast = async () => {
    try {
      await castContent(id, Number(castContentId))
      setCastDialog(false)
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
        <Button variant="outlined" startIcon={<CastIcon />} onClick={openCast} disabled={closed}>
          投放内容
        </Button>
        <Button variant="outlined" color="error" startIcon={<CloseIcon />} onClick={doClose} disabled={closed}>
          关闭房间
        </Button>
      </Box>

      {room.understaffedAlert && (
        <Alert severity="error" sx={{ mb: 2 }}>
          红灯预警: 该房间缺人状态已超过 3 分钟(在线 {room.onlineMemberCount}/2)
        </Alert>
      )}

      <Grid container spacing={2.5}>
        <Grid item xs={12} md={4}>
          <Card sx={{ mb: 2.5 }}>
            <CardContent>
              <Typography variant="h6" sx={{ mb: 2 }}>会议时间</Typography>
              <Typography variant="h4" sx={{ fontVariantNumeric: 'tabular-nums', mb: 1 }}>
                {room.status === 'RUNNING' ? formatSeconds(remaining) : '--:--'}
              </Typography>
              <LinearProgress variant="determinate" value={progress} sx={{ mb: 1.5, height: 8, borderRadius: 4 }} />
              <Typography variant="body2" color="text.secondary">
                会议时长 {room.durationMinutes} 分钟 · 到期自动关闭
              </Typography>
              {room.meetingStartAt && (
                <Typography variant="body2" color="text.secondary">
                  开始: {room.meetingStartAt.replace('T', ' ')}
                </Typography>
              )}
              {room.meetingEndAt && (
                <Typography variant="body2" color="text.secondary">
                  预计结束: {room.meetingEndAt.replace('T', ' ')}
                </Typography>
              )}
            </CardContent>
          </Card>

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

        <Grid item xs={12} md={4}>
          <Card sx={{ mb: 2.5 }}>
            <CardContent>
              <Typography variant="h6" sx={{ mb: 2 }}>
                当前投放 / 播放状态
              </Typography>
              <Typography variant="body1" sx={{ mb: 1 }}>
                内容: {room.contentName || '未投放'}
              </Typography>
              <Box sx={{ display: 'flex', gap: 1, mb: 1 }}>
                <Chip
                  size="small"
                  label={{ IDLE: '空闲', PLAYING: '播放中', PAUSED: '已暂停' }[room.playbackState] || room.playbackState}
                  color={room.playbackState === 'PLAYING' ? 'success' : 'default'}
                />
                <Chip size="small" label={`进度 ${formatSeconds(room.playbackPositionSeconds)}`} />
              </Box>
              <Typography variant="body2" color="text.secondary">
                播放/暂停/进度由手机客户端控制, 此处为实时同步的权威状态
              </Typography>
            </CardContent>
          </Card>

          <Card>
            <CardContent>
              <Typography variant="h6" sx={{ mb: 2 }}>
                <SmartphoneIcon sx={{ verticalAlign: 'middle', mr: 1 }} />
                手机客户端({room.onlineMemberCount}/2 在线)
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
        </Grid>

        <Grid item xs={12} md={4}>
          <Card sx={{ mb: 2.5 }}>
            <CardContent>
              <Typography variant="h6" sx={{ mb: 2 }}>
                <FavoriteIcon sx={{ verticalAlign: 'middle', mr: 1, color: '#ec407a' }} />
                点赞记录(共 {room.likeCount})
              </Typography>
              <List dense disablePadding sx={{ maxHeight: 220, overflow: 'auto' }}>
                {likes.map((like) => (
                  <ListItem key={like.id} disableGutters>
                    <ListItemText
                      primary={like.nickname}
                      secondary={like.likedAt?.replace('T', ' ')}
                    />
                  </ListItem>
                ))}
                {likes.length === 0 && <Typography color="text.secondary">暂无点赞</Typography>}
              </List>
            </CardContent>
          </Card>

          <Card>
            <CardContent>
              <Typography variant="h6" sx={{ mb: 2 }}>事件日志</Typography>
              <Table size="small">
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
                      <TableCell sx={{ maxWidth: 180, wordBreak: 'break-all' }}>{event.detail}</TableCell>
                      <TableCell>{event.createdAt?.replace('T', ' ')}</TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </CardContent>
          </Card>
        </Grid>
      </Grid>

      <Dialog open={castDialog} onClose={() => setCastDialog(false)} maxWidth="xs" fullWidth>
        <DialogTitle>投放内容到房间 {room.roomCode}</DialogTitle>
        <DialogContent sx={{ pt: '12px !important' }}>
          <TextField
            select
            fullWidth
            label="选择内容"
            value={castContentId}
            onChange={(e) => setCastContentId(e.target.value)}
          >
            {contents.map((content) => (
              <MenuItem key={content.id} value={content.id}>
                {content.name}（{content.type}）
              </MenuItem>
            ))}
          </TextField>
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setCastDialog(false)}>取消</Button>
          <Button variant="contained" onClick={doCast} disabled={!castContentId}>
            立即投放
          </Button>
        </DialogActions>
      </Dialog>
    </Box>
  )
}
