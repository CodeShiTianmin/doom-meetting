import { useCallback, useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import {
  Box, Button, Card, CardContent, Dialog, DialogActions, DialogContent,
  DialogTitle, FormControlLabel, MenuItem, Switch, Table, TableBody, TableCell,
  TableHead, TableRow, TextField, ToggleButton, ToggleButtonGroup, Typography,
} from '@mui/material'
import AddIcon from '@mui/icons-material/Add'
import { createRoom, listContents, listRooms } from '../api'
import { subscribeAdminDashboard } from '../api/ws'
import RoomStatusChip from '../components/RoomStatusChip.jsx'
import RedAlertLight from '../components/RedAlertLight.jsx'

export default function RoomsPage() {
  const navigate = useNavigate()
  const [rooms, setRooms] = useState([])
  const [statusFilter, setStatusFilter] = useState('')
  const [contents, setContents] = useState([])
  const [dialogOpen, setDialogOpen] = useState(false)
  const [form, setForm] = useState({
    name: '',
    durationMinutes: 60,
    videoCallEnabled: true,
    cameraEnabled: true,
    contentId: '',
  })
  const [error, setError] = useState('')

  const refresh = useCallback(async () => {
    setRooms(await listRooms(statusFilter || undefined))
  }, [statusFilter])

  useEffect(() => {
    refresh().catch(() => {})
    const unsubscribe = subscribeAdminDashboard(() => refresh().catch(() => {}))
    return unsubscribe
  }, [refresh])

  const openDialog = async () => {
    setError('')
    setDialogOpen(true)
    try {
      setContents(await listContents())
    } catch {
      setContents([])
    }
  }

  const submit = async () => {
    setError('')
    try {
      const created = await createRoom({
        name: form.name,
        durationMinutes: Number(form.durationMinutes),
        videoCallEnabled: form.videoCallEnabled,
        cameraEnabled: form.cameraEnabled,
        contentId: form.contentId || null,
      })
      setDialogOpen(false)
      setForm({ name: '', durationMinutes: 60, videoCallEnabled: true, cameraEnabled: true, contentId: '' })
      navigate(`/rooms/${created.id}`)
    } catch (err) {
      setError(err.message)
    }
  }

  return (
    <Box>
      <Box sx={{ display: 'flex', alignItems: 'center', mb: 3, gap: 2 }}>
        <Typography variant="h5" sx={{ flexGrow: 1 }}>房间管理</Typography>
        <ToggleButtonGroup
          size="small"
          exclusive
          value={statusFilter}
          onChange={(e, value) => setStatusFilter(value ?? '')}
        >
          <ToggleButton value="">全部</ToggleButton>
          <ToggleButton value="WAITING">等待中</ToggleButton>
          <ToggleButton value="RUNNING">运行中</ToggleButton>
          <ToggleButton value="CLOSED">已关闭</ToggleButton>
        </ToggleButtonGroup>
        <Button variant="contained" startIcon={<AddIcon />} onClick={openDialog}>
          创建房间
        </Button>
      </Box>

      <Card>
        <CardContent>
          <Table>
            <TableHead>
              <TableRow>
                <TableCell>预警</TableCell>
                <TableCell>房间</TableCell>
                <TableCell>房号</TableCell>
                <TableCell>状态</TableCell>
                <TableCell>在线人数</TableCell>
                <TableCell>当前内容</TableCell>
                <TableCell>会议时长</TableCell>
                <TableCell>点赞</TableCell>
                <TableCell>创建时间</TableCell>
              </TableRow>
            </TableHead>
            <TableBody>
              {rooms.map((room) => (
                <TableRow
                  key={room.id}
                  hover
                  sx={{ cursor: 'pointer' }}
                  onClick={() => navigate(`/rooms/${room.id}`)}
                >
                  <TableCell><RedAlertLight on={room.understaffedAlert} /></TableCell>
                  <TableCell>{room.name}</TableCell>
                  <TableCell>{room.roomCode}</TableCell>
                  <TableCell><RoomStatusChip status={room.status} /></TableCell>
                  <TableCell>{room.onlineMemberCount}/2</TableCell>
                  <TableCell>{room.contentName || '-'}</TableCell>
                  <TableCell>{room.durationMinutes} 分钟</TableCell>
                  <TableCell>{room.likeCount}</TableCell>
                  <TableCell>{room.createdAt?.replace('T', ' ')}</TableCell>
                </TableRow>
              ))}
              {rooms.length === 0 && (
                <TableRow>
                  <TableCell colSpan={9}>
                    <Typography color="text.secondary" align="center" sx={{ py: 3 }}>
                      暂无房间
                    </Typography>
                  </TableCell>
                </TableRow>
              )}
            </TableBody>
          </Table>
        </CardContent>
      </Card>

      <Dialog open={dialogOpen} onClose={() => setDialogOpen(false)} maxWidth="xs" fullWidth>
        <DialogTitle>创建房间</DialogTitle>
        <DialogContent sx={{ display: 'flex', flexDirection: 'column', gap: 2, pt: '12px !important' }}>
          {error && <Typography color="error" variant="body2">{error}</Typography>}
          <TextField
            label="房间名称"
            value={form.name}
            onChange={(e) => setForm({ ...form, name: e.target.value })}
          />
          <TextField
            label="会议时长(分钟)"
            type="number"
            inputProps={{ min: 1, max: 720 }}
            value={form.durationMinutes}
            onChange={(e) => setForm({ ...form, durationMinutes: e.target.value })}
          />
          <TextField
            select
            label="初始投放内容(可选)"
            value={form.contentId}
            onChange={(e) => setForm({ ...form, contentId: e.target.value })}
          >
            <MenuItem value="">暂不投放</MenuItem>
            {contents.map((content) => (
              <MenuItem key={content.id} value={content.id}>{content.name}</MenuItem>
            ))}
          </TextField>
          <FormControlLabel
            control={
              <Switch
                checked={form.videoCallEnabled}
                onChange={(e) => setForm({ ...form, videoCallEnabled: e.target.checked })}
              />
            }
            label="开放手机端视频通话"
          />
          <FormControlLabel
            control={
              <Switch
                checked={form.cameraEnabled}
                onChange={(e) => setForm({ ...form, cameraEnabled: e.target.checked })}
              />
            }
            label="开放手机端摄像头"
          />
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setDialogOpen(false)}>取消</Button>
          <Button variant="contained" onClick={submit} disabled={!form.name || !form.durationMinutes}>
            创建
          </Button>
        </DialogActions>
      </Dialog>
    </Box>
  )
}
