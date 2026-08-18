import { useCallback, useEffect, useState } from 'react'
import {
  Alert, Box, Button, Card, CardContent, Chip, Dialog, DialogActions,
  DialogContent, DialogTitle, MenuItem, Table, TableBody, TableCell, TableHead,
  TableRow, TextField, Typography,
} from '@mui/material'
import AddIcon from '@mui/icons-material/Add'
import CancelIcon from '@mui/icons-material/Cancel'
import { cancelSchedule, createSchedule, listContents, listRooms, listSchedules } from '../api'

const statusMap = {
  PENDING: { label: '待执行', color: 'warning' },
  EXECUTED: { label: '已执行', color: 'success' },
  CANCELLED: { label: '已取消', color: 'default' },
  FAILED: { label: '执行失败', color: 'error' },
}

export default function SchedulesPage() {
  const [schedules, setSchedules] = useState([])
  const [rooms, setRooms] = useState([])
  const [contents, setContents] = useState([])
  const [dialogOpen, setDialogOpen] = useState(false)
  const [form, setForm] = useState({ roomId: '', contentId: '', castAt: '', note: '' })
  const [error, setError] = useState('')

  const refresh = useCallback(async () => {
    setSchedules(await listSchedules())
  }, [])

  useEffect(() => {
    refresh().catch((err) => setError(err.message))
    const timer = setInterval(() => refresh().catch(() => {}), 10000)
    return () => clearInterval(timer)
  }, [refresh])

  const openDialog = async () => {
    setDialogOpen(true)
    try {
      const [r, c] = await Promise.all([listRooms(), listContents()])
      setRooms(r.filter((room) => room.status !== 'CLOSED'))
      setContents(c)
    } catch {
      setRooms([])
      setContents([])
    }
  }

  const submit = async () => {
    setError('')
    try {
      await createSchedule({
        roomId: Number(form.roomId),
        contentId: Number(form.contentId),
        castAt: form.castAt,
        note: form.note || null,
      })
      setDialogOpen(false)
      setForm({ roomId: '', contentId: '', castAt: '', note: '' })
      await refresh()
    } catch (err) {
      setError(err.message)
    }
  }

  const cancel = async (schedule) => {
    try {
      await cancelSchedule(schedule.id)
      await refresh()
    } catch (err) {
      setError(err.message)
    }
  }

  return (
    <Box>
      <Box sx={{ display: 'flex', alignItems: 'center', mb: 3 }}>
        <Typography variant="h5" sx={{ flexGrow: 1 }}>投放计划</Typography>
        <Button variant="contained" startIcon={<AddIcon />} onClick={openDialog}>
          新建计划
        </Button>
      </Box>
      {error && <Alert severity="error" sx={{ mb: 2 }} onClose={() => setError('')}>{error}</Alert>}
      <Alert severity="info" sx={{ mb: 2 }}>
        不同时间可将不同内容投给不同房间, 各房间独立运行、互不串音串频。
        例: 8:00 将内容1投给 A 房间, 8:01 将内容2投给 B 房间。
      </Alert>
      <Card>
        <CardContent>
          <Table>
            <TableHead>
              <TableRow>
                <TableCell>房间</TableCell>
                <TableCell>内容</TableCell>
                <TableCell>投放时间</TableCell>
                <TableCell>状态</TableCell>
                <TableCell>执行时间</TableCell>
                <TableCell>备注</TableCell>
                <TableCell align="right">操作</TableCell>
              </TableRow>
            </TableHead>
            <TableBody>
              {schedules.map((schedule) => {
                const status = statusMap[schedule.status] || { label: schedule.status, color: 'default' }
                return (
                  <TableRow key={schedule.id} hover>
                    <TableCell>{schedule.roomName}（{schedule.roomCode}）</TableCell>
                    <TableCell>{schedule.contentName}</TableCell>
                    <TableCell>{schedule.castAt?.replace('T', ' ')}</TableCell>
                    <TableCell><Chip size="small" label={status.label} color={status.color} /></TableCell>
                    <TableCell>{schedule.executedAt?.replace('T', ' ') || '-'}</TableCell>
                    <TableCell>{schedule.note || '-'}</TableCell>
                    <TableCell align="right">
                      {schedule.status === 'PENDING' && (
                        <Button
                          size="small"
                          color="error"
                          startIcon={<CancelIcon />}
                          onClick={() => cancel(schedule)}
                        >
                          取消
                        </Button>
                      )}
                    </TableCell>
                  </TableRow>
                )
              })}
              {schedules.length === 0 && (
                <TableRow>
                  <TableCell colSpan={7}>
                    <Typography color="text.secondary" align="center" sx={{ py: 3 }}>
                      暂无投放计划
                    </Typography>
                  </TableCell>
                </TableRow>
              )}
            </TableBody>
          </Table>
        </CardContent>
      </Card>

      <Dialog open={dialogOpen} onClose={() => setDialogOpen(false)} maxWidth="xs" fullWidth>
        <DialogTitle>新建投放计划</DialogTitle>
        <DialogContent sx={{ display: 'flex', flexDirection: 'column', gap: 2, pt: '12px !important' }}>
          <TextField
            select
            label="目标房间"
            value={form.roomId}
            onChange={(e) => setForm({ ...form, roomId: e.target.value })}
          >
            {rooms.map((room) => (
              <MenuItem key={room.id} value={room.id}>
                {room.name}（{room.roomCode}）
              </MenuItem>
            ))}
          </TextField>
          <TextField
            select
            label="投放内容"
            value={form.contentId}
            onChange={(e) => setForm({ ...form, contentId: e.target.value })}
          >
            {contents.map((content) => (
              <MenuItem key={content.id} value={content.id}>{content.name}</MenuItem>
            ))}
          </TextField>
          <TextField
            label="投放时间"
            type="datetime-local"
            InputLabelProps={{ shrink: true }}
            value={form.castAt}
            onChange={(e) => setForm({ ...form, castAt: e.target.value })}
          />
          <TextField
            label="备注(可选)"
            value={form.note}
            onChange={(e) => setForm({ ...form, note: e.target.value })}
          />
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setDialogOpen(false)}>取消</Button>
          <Button
            variant="contained"
            onClick={submit}
            disabled={!form.roomId || !form.contentId || !form.castAt}
          >
            创建
          </Button>
        </DialogActions>
      </Dialog>
    </Box>
  )
}
