import { useCallback, useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import {
  Box, Card, CardContent, Chip, Grid, List, ListItem, ListItemText, Typography,
} from '@mui/material'
import MeetingRoomIcon from '@mui/icons-material/MeetingRoom'
import PlayCircleIcon from '@mui/icons-material/PlayCircle'
import HourglassTopIcon from '@mui/icons-material/HourglassTop'
import FavoriteIcon from '@mui/icons-material/Favorite'
import MovieIcon from '@mui/icons-material/Movie'
import ScheduleIcon from '@mui/icons-material/Schedule'
import { getDashboardSummary, listRooms } from '../api'
import { subscribeAdminDashboard } from '../api/ws'
import RoomStatusChip from '../components/RoomStatusChip.jsx'
import RedAlertLight from '../components/RedAlertLight.jsx'

function StatCard({ icon, label, value, color }) {
  return (
    <Card sx={{ height: '100%' }}>
      <CardContent sx={{ display: 'flex', alignItems: 'center', gap: 2 }}>
        <Box
          sx={{
            width: 52, height: 52, borderRadius: 3, display: 'flex',
            alignItems: 'center', justifyContent: 'center',
            background: `${color}22`, color,
          }}
        >
          {icon}
        </Box>
        <Box>
          <Typography variant="h5">{value}</Typography>
          <Typography variant="body2" color="text.secondary">{label}</Typography>
        </Box>
      </CardContent>
    </Card>
  )
}

export default function DashboardPage() {
  const navigate = useNavigate()
  const [summary, setSummary] = useState(null)
  const [rooms, setRooms] = useState([])
  const [events, setEvents] = useState([])

  const refresh = useCallback(async () => {
    const [s, r] = await Promise.all([getDashboardSummary(), listRooms()])
    setSummary(s)
    setRooms(r)
  }, [])

  useEffect(() => {
    refresh().catch(() => {})
    const unsubscribe = subscribeAdminDashboard((event) => {
      setEvents((prev) => [event, ...prev].slice(0, 30))
      refresh().catch(() => {})
    })
    return unsubscribe
  }, [refresh])

  const activeRooms = rooms.filter((room) => room.status !== 'CLOSED')

  return (
    <Box>
      <Typography variant="h5" sx={{ mb: 3 }}>仪表盘</Typography>
      <Grid container spacing={2.5} sx={{ mb: 3 }}>
        <Grid item xs={12} sm={6} md={2}>
          <StatCard icon={<MeetingRoomIcon />} label="全部房间" value={summary?.totalRooms ?? '-'} color="#3f51e0" />
        </Grid>
        <Grid item xs={12} sm={6} md={2}>
          <StatCard icon={<HourglassTopIcon />} label="等待中" value={summary?.waitingRooms ?? '-'} color="#fb8c00" />
        </Grid>
        <Grid item xs={12} sm={6} md={2}>
          <StatCard icon={<PlayCircleIcon />} label="运行中" value={summary?.runningRooms ?? '-'} color="#00bfa5" />
        </Grid>
        <Grid item xs={12} sm={6} md={2}>
          <StatCard icon={<MeetingRoomIcon />} label="红灯预警" value={summary?.alertRooms ?? '-'} color="#e53935" />
        </Grid>
        <Grid item xs={12} sm={6} md={2}>
          <StatCard icon={<FavoriteIcon />} label="今日点赞" value={summary?.todayLikes ?? '-'} color="#ec407a" />
        </Grid>
        <Grid item xs={12} sm={6} md={2}>
          <StatCard icon={<ScheduleIcon />} label="待执行计划" value={summary?.pendingSchedules ?? '-'} color="#8e24aa" />
        </Grid>
      </Grid>

      <Grid container spacing={2.5}>
        <Grid item xs={12} md={7}>
          <Card>
            <CardContent>
              <Typography variant="h6" sx={{ mb: 2 }}>活动房间</Typography>
              {activeRooms.length === 0 && (
                <Typography color="text.secondary">暂无等待/运行中的房间</Typography>
              )}
              <List disablePadding>
                {activeRooms.map((room) => (
                  <ListItem
                    key={room.id}
                    sx={{
                      mb: 1, borderRadius: 2, border: '1px solid #edf0f7',
                      cursor: 'pointer', '&:hover': { background: '#f7f8fd' },
                    }}
                    onClick={() => navigate(`/rooms/${room.id}`)}
                    secondaryAction={
                      <Box sx={{ display: 'flex', alignItems: 'center', gap: 1.5 }}>
                        <RedAlertLight on={room.understaffedAlert} />
                        <RoomStatusChip status={room.status} />
                      </Box>
                    }
                  >
                    <ListItemText
                      primary={`${room.name}（${room.roomCode}）`}
                      secondary={`在线 ${room.onlineMemberCount}/${room.maxMembers ?? 2} · 点赞 ${room.likeCount} · 当前内容: ${room.contentName || '未投放'}`}
                    />
                  </ListItem>
                ))}
              </List>
            </CardContent>
          </Card>
        </Grid>
        <Grid item xs={12} md={5}>
          <Card>
            <CardContent>
              <Typography variant="h6" sx={{ mb: 2 }}>实时事件</Typography>
              {events.length === 0 && (
                <Typography color="text.secondary">等待实时事件推送…</Typography>
              )}
              <List dense disablePadding sx={{ maxHeight: 420, overflow: 'auto' }}>
                {events.map((event, index) => (
                  <ListItem key={index} disableGutters>
                    <ListItemText
                      primary={
                        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                          <Chip
                            size="small"
                            label={event.type}
                            color={event.type === 'UNDERSTAFFED_ALERT' ? 'error' : 'default'}
                          />
                          <Typography variant="body2">{event.roomCode || ''}</Typography>
                        </Box>
                      }
                      secondary={event.timestamp}
                    />
                  </ListItem>
                ))}
              </List>
            </CardContent>
          </Card>
        </Grid>
      </Grid>
    </Box>
  )
}
