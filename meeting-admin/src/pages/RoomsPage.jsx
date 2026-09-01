import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import {
  Alert, Box, Button, Card, CircularProgress, Dialog, DialogActions, DialogContent,
  DialogTitle, FormControlLabel, IconButton, InputAdornment, LinearProgress, Stack, Switch,
  Table, TableBody, TableCell, TableContainer, TableHead, TableRow, TextField, ToggleButton,
  ToggleButtonGroup, Tooltip, Typography,
} from '@mui/material'
import AddIcon from '@mui/icons-material/Add'
import SearchIcon from '@mui/icons-material/Search'
import RefreshIcon from '@mui/icons-material/Refresh'
import MeetingRoomIcon from '@mui/icons-material/MeetingRoom'
import FavoriteIcon from '@mui/icons-material/Favorite'
import { createRoom, listRooms } from '../api'
import { subscribeAdminDashboard } from '../api/ws'
import RoomStatusChip from '../components/RoomStatusChip.jsx'
import RedAlertLight from '../components/RedAlertLight.jsx'
import PageHeader from '../components/PageHeader.jsx'
import EmptyState from '../components/EmptyState.jsx'

const CAST_LABELS = { SCREEN: '屏幕共享', VIDEO: '视频推流', CAMERA: '摄像头推流' }
const STATUS_FILTERS = [
  { value: '', label: '全部' },
  { value: 'SCHEDULED', label: '已预约' },
  { value: 'WAITING', label: '等待中' },
  { value: 'RUNNING', label: '运行中' },
  { value: 'CLOSED', label: '已关闭' },
]
const DEFAULT_FORM = {
  name: '',
  durationMinutes: 60,
  maxMembers: 2,
  videoCallEnabled: true,
  cameraEnabled: true,
  approvalRequired: false,
  scheduledStartAt: '',
}
const REFRESH_DEBOUNCE_MS = 600

function validateForm(form) {
  const errors = {}
  if (!form.name.trim()) errors.name = '请输入房间名称'
  const duration = Number(form.durationMinutes)
  if (!Number.isInteger(duration) || duration < 1 || duration > 720) errors.durationMinutes = '1 ~ 720 分钟'
  const members = Number(form.maxMembers)
  if (!Number.isInteger(members) || members < 1 || members > 50) errors.maxMembers = '1 ~ 50 人'
  if (form.scheduledStartAt) {
    const when = new Date(form.scheduledStartAt)
    if (Number.isNaN(when.getTime())) errors.scheduledStartAt = '时间格式不正确'
    else if (when.getTime() < Date.now()) errors.scheduledStartAt = '预约时间需晚于当前时间'
  }
  return errors
}

export default function RoomsPage() {
  const navigate = useNavigate()
  const [rooms, setRooms] = useState([])
  const [statusFilter, setStatusFilter] = useState('')
  const [keyword, setKeyword] = useState('')
  const [loading, setLoading] = useState(true)
  const [refreshing, setRefreshing] = useState(false)
  const [loadError, setLoadError] = useState('')
  const [dialogOpen, setDialogOpen] = useState(false)
  const [form, setForm] = useState(DEFAULT_FORM)
  const [submitting, setSubmitting] = useState(false)
  const [error, setError] = useState('')
  const debounceRef = useRef(null)

  const refresh = useCallback(async (silent = false) => {
    if (!silent) setRefreshing(true)
    try {
      const list = await listRooms(statusFilter || undefined)
      setRooms(Array.isArray(list) ? list : [])
      setLoadError('')
    } catch (err) {
      setLoadError(err.message || '加载房间列表失败')
    } finally {
      setLoading(false)
      setRefreshing(false)
    }
  }, [statusFilter])

  useEffect(() => {
    setLoading(true)
    refresh()
  }, [refresh])

  useEffect(() => {
    const unsubscribe = subscribeAdminDashboard(() => {
      clearTimeout(debounceRef.current)
      debounceRef.current = setTimeout(() => refresh(true), REFRESH_DEBOUNCE_MS)
    })
    return () => {
      clearTimeout(debounceRef.current)
      unsubscribe()
    }
  }, [refresh])

  const filteredRooms = useMemo(() => {
    const kw = keyword.trim().toLowerCase()
    if (!kw) return rooms
    return rooms.filter((room) =>
      (room.name || '').toLowerCase().includes(kw) || (room.roomCode || '').toLowerCase().includes(kw))
  }, [rooms, keyword])

  const formErrors = useMemo(() => validateForm(form), [form])
  const formValid = Object.keys(formErrors).length === 0

  const openDialog = () => {
    setError('')
    setForm(DEFAULT_FORM)
    setDialogOpen(true)
  }

  const closeDialog = () => {
    if (submitting) return
    setDialogOpen(false)
  }

  const submit = async () => {
    if (submitting || !formValid) return
    setError('')
    setSubmitting(true)
    try {
      const created = await createRoom({
        name: form.name.trim(),
        durationMinutes: Number(form.durationMinutes),
        maxMembers: Number(form.maxMembers),
        videoCallEnabled: form.videoCallEnabled,
        cameraEnabled: form.videoCallEnabled && form.cameraEnabled,
        approvalRequired: form.approvalRequired,
        scheduledStartAt: form.scheduledStartAt || null,
      })
      setDialogOpen(false)
      setForm(DEFAULT_FORM)
      navigate(`/rooms/${created.id}`)
    } catch (err) {
      setError(err.message || '创建失败, 请稍后重试')
    } finally {
      setSubmitting(false)
    }
  }

  const updateField = (field) => (e) => {
    const value = e.target.type === 'checkbox' ? e.target.checked : e.target.value
    setForm((prev) => ({ ...prev, [field]: value }))
  }

  return (
    <Box>
      <PageHeader
        title="房间管理"
        subtitle={`共 ${rooms.length} 个房间${keyword.trim() ? ` · 匹配 ${filteredRooms.length} 个` : ''}`}
        actions={(
          <>
            <Tooltip title="刷新">
              <IconButton onClick={() => refresh()} disabled={refreshing} aria-label="刷新">
                <RefreshIcon />
              </IconButton>
            </Tooltip>
            <Button variant="contained" startIcon={<AddIcon />} onClick={openDialog}>
              创建房间
            </Button>
          </>
        )}
      />

      <Card sx={{ mb: 2 }}>
        <Stack
          direction={{ xs: 'column', md: 'row' }}
          spacing={1.5}
          alignItems={{ xs: 'stretch', md: 'center' }}
          justifyContent="space-between"
          sx={{ p: 2 }}
        >
          <ToggleButtonGroup
            size="small"
            exclusive
            value={statusFilter}
            onChange={(e, value) => setStatusFilter(value ?? '')}
            sx={{ flexWrap: 'wrap' }}
            aria-label="状态筛选"
          >
            {STATUS_FILTERS.map((item) => (
              <ToggleButton key={item.value} value={item.value} sx={{ px: 1.75 }}>{item.label}</ToggleButton>
            ))}
          </ToggleButtonGroup>
          <TextField
            size="small"
            placeholder="搜索房间名称 / 房号"
            value={keyword}
            onChange={(e) => setKeyword(e.target.value)}
            sx={{ minWidth: { md: 260 } }}
            InputProps={{
              startAdornment: (
                <InputAdornment position="start">
                  <SearchIcon fontSize="small" color="action" />
                </InputAdornment>
              ),
            }}
          />
        </Stack>
      </Card>

      {loadError && (
        <Alert
          severity="error"
          sx={{ mb: 2 }}
          action={<Button color="inherit" size="small" onClick={() => refresh()}>重试</Button>}
        >
          {loadError}
        </Alert>
      )}

      <Card sx={{ overflow: 'hidden' }}>
        {refreshing && !loading && <LinearProgress sx={{ height: 2 }} />}
        {loading ? (
          <Box sx={{ py: 8, display: 'flex', justifyContent: 'center' }}>
            <CircularProgress />
          </Box>
        ) : filteredRooms.length === 0 ? (
          <EmptyState
            icon={MeetingRoomIcon}
            title={keyword.trim() ? '没有匹配的房间' : '暂无房间'}
            description={keyword.trim() ? '换个关键词试试' : '点击右上角“创建房间”开始第一场会议'}
            action={!keyword.trim() && (
              <Button variant="outlined" startIcon={<AddIcon />} onClick={openDialog}>创建房间</Button>
            )}
          />
        ) : (
          <TableContainer>
            <Table sx={{ minWidth: 880 }}>
              <TableHead>
                <TableRow>
                  <TableCell width={56}>预警</TableCell>
                  <TableCell>房间</TableCell>
                  <TableCell>房号</TableCell>
                  <TableCell>状态</TableCell>
                  <TableCell>在线人数</TableCell>
                  <TableCell>当前推流</TableCell>
                  <TableCell>会议时长</TableCell>
                  <TableCell>点赞</TableCell>
                  <TableCell>创建时间</TableCell>
                </TableRow>
              </TableHead>
              <TableBody>
                {filteredRooms.map((room) => {
                  const maxMembers = room.maxMembers ?? 2
                  const online = room.onlineMemberCount ?? 0
                  const full = online >= maxMembers
                  return (
                    <TableRow
                      key={room.id}
                      hover
                      sx={{ cursor: 'pointer' }}
                      onClick={() => navigate(`/rooms/${room.id}`)}
                    >
                      <TableCell><RedAlertLight on={room.understaffedAlert} since={room.understaffedSince} /></TableCell>
                      <TableCell>
                        <Typography variant="body2" sx={{ fontWeight: 600 }}>{room.name}</Typography>
                        {room.scheduledStartAt && room.status === 'SCHEDULED' && (
                          <Typography variant="caption" color="text.secondary">
                            预约 {room.scheduledStartAt.replace('T', ' ').slice(0, 16)}
                          </Typography>
                        )}
                      </TableCell>
                      <TableCell sx={{ fontFamily: 'monospace', fontWeight: 600 }}>{room.roomCode}</TableCell>
                      <TableCell><RoomStatusChip status={room.status} /></TableCell>
                      <TableCell>
                        <Typography
                          variant="body2"
                          sx={{ fontWeight: 600, color: full ? 'success.main' : online > 0 ? 'warning.main' : 'text.secondary' }}
                        >
                          {online}/{maxMembers}
                        </Typography>
                      </TableCell>
                      <TableCell>
                        {room.castType ? (
                          <Typography variant="body2" noWrap sx={{ maxWidth: 220 }} title={room.castLabel || ''}>
                            {CAST_LABELS[room.castType] || room.castType}
                            {room.castLabel ? ` · ${room.castLabel}` : ''}
                          </Typography>
                        ) : (
                          <Typography variant="body2" color="text.disabled">-</Typography>
                        )}
                      </TableCell>
                      <TableCell>{room.durationMinutes} 分钟</TableCell>
                      <TableCell>
                        <Stack direction="row" alignItems="center" spacing={0.5}>
                          <FavoriteIcon sx={{ fontSize: 14, color: '#ec407a' }} />
                          <span>{room.likeCount ?? 0}</span>
                        </Stack>
                      </TableCell>
                      <TableCell sx={{ whiteSpace: 'nowrap', color: 'text.secondary' }}>
                        {room.createdAt?.replace('T', ' ').slice(0, 19)}
                      </TableCell>
                    </TableRow>
                  )
                })}
              </TableBody>
            </Table>
          </TableContainer>
        )}
      </Card>

      <Dialog open={dialogOpen} onClose={closeDialog} maxWidth="xs" fullWidth>
        <DialogTitle>创建房间</DialogTitle>
        <DialogContent sx={{ display: 'flex', flexDirection: 'column', gap: 2, pt: '12px !important' }}>
          {error && <Alert severity="error">{error}</Alert>}
          <TextField
            label="房间名称"
            autoFocus
            value={form.name}
            onChange={updateField('name')}
            error={Boolean(form.name && formErrors.name)}
            inputProps={{ maxLength: 64 }}
          />
          <Stack direction="row" spacing={2}>
            <TextField
              label="会议时长(分钟)"
              type="number"
              fullWidth
              inputProps={{ min: 1, max: 720 }}
              value={form.durationMinutes}
              onChange={updateField('durationMinutes')}
              error={Boolean(formErrors.durationMinutes)}
              helperText={formErrors.durationMinutes || ' '}
            />
            <TextField
              label="成员数上限"
              type="number"
              fullWidth
              inputProps={{ min: 1, max: 50 }}
              value={form.maxMembers}
              onChange={updateField('maxMembers')}
              error={Boolean(formErrors.maxMembers)}
              helperText={formErrors.maxMembers || '手机客户端数量'}
            />
          </Stack>
          <FormControlLabel
            control={<Switch checked={form.videoCallEnabled} onChange={updateField('videoCallEnabled')} />}
            label="开放手机端视频通话"
          />
          <FormControlLabel
            control={(
              <Switch
                checked={form.cameraEnabled && form.videoCallEnabled}
                disabled={!form.videoCallEnabled}
                onChange={updateField('cameraEnabled')}
              />
            )}
            label="开放手机端摄像头"
          />
          <FormControlLabel
            control={<Switch checked={form.approvalRequired} onChange={updateField('approvalRequired')} />}
            label="开启等候室(入会需审批)"
          />
          <TextField
            label="预约开会时间(可选)"
            type="datetime-local"
            InputLabelProps={{ shrink: true }}
            value={form.scheduledStartAt}
            onChange={updateField('scheduledStartAt')}
            error={Boolean(formErrors.scheduledStartAt)}
            helperText={formErrors.scheduledStartAt || '不选则创建后立即进入等待状态'}
          />
        </DialogContent>
        <DialogActions sx={{ px: 3, pb: 2 }}>
          <Button onClick={closeDialog} disabled={submitting}>取消</Button>
          <Button
            variant="contained"
            onClick={submit}
            disabled={!formValid || submitting}
            startIcon={submitting ? <CircularProgress size={16} color="inherit" /> : null}
          >
            创建
          </Button>
        </DialogActions>
      </Dialog>
    </Box>
  )
}
