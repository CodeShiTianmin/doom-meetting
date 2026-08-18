import { useCallback, useEffect, useState } from 'react'
import { Box, Card, CardContent, Grid, Typography } from '@mui/material'
import {
  Area, AreaChart, CartesianGrid, ResponsiveContainer, Tooltip, XAxis, YAxis,
} from 'recharts'
import MeetingRoomIcon from '@mui/icons-material/MeetingRoom'
import PlayCircleIcon from '@mui/icons-material/PlayCircle'
import HourglassTopIcon from '@mui/icons-material/HourglassTop'
import DoorFrontIcon from '@mui/icons-material/DoorFront'
import WarningAmberIcon from '@mui/icons-material/WarningAmber'
import FavoriteIcon from '@mui/icons-material/Favorite'
import FavoriteBorderIcon from '@mui/icons-material/FavoriteBorder'
import ScheduleIcon from '@mui/icons-material/Schedule'
import { getDashboardSummary, getDashboardTrends } from '../api'
import { subscribeAdminDashboard } from '../api/ws'

function StatCard({ icon, label, value, color }) {
  return (
    <Card
      sx={{
        height: '100%',
        position: 'relative',
        overflow: 'hidden',
        '&:hover': { transform: 'translateY(-3px)', boxShadow: `0 10px 28px ${color}33` },
        '&::before': {
          content: '""',
          position: 'absolute',
          top: 0, left: 0, right: 0, height: 4,
          background: `linear-gradient(90deg, ${color}, ${color}88)`,
        },
      }}
    >
      <CardContent sx={{ display: 'flex', alignItems: 'center', gap: 2 }}>
        <Box
          sx={{
            width: 52, height: 52, borderRadius: 3, display: 'flex',
            alignItems: 'center', justifyContent: 'center',
            background: `linear-gradient(135deg, ${color}26, ${color}12)`, color,
          }}
        >
          {icon}
        </Box>
        <Box>
          <Typography variant="h5" sx={{ fontVariantNumeric: 'tabular-nums' }}>{value}</Typography>
          <Typography variant="body2" color="text.secondary">{label}</Typography>
        </Box>
      </CardContent>
    </Card>
  )
}

function TrendChart({ title, data, dataKey, name, color }) {
  const gradientId = `grad-${dataKey}`
  return (
    <Card>
      <CardContent>
        <Typography variant="h6" sx={{ mb: 2 }}>{title}</Typography>
        <Box sx={{ height: 300 }}>
          <ResponsiveContainer width="100%" height="100%">
            <AreaChart data={data} margin={{ top: 8, right: 16, left: -12, bottom: 0 }}>
              <defs>
                <linearGradient id={gradientId} x1="0" y1="0" x2="0" y2="1">
                  <stop offset="5%" stopColor={color} stopOpacity={0.35} />
                  <stop offset="95%" stopColor={color} stopOpacity={0.02} />
                </linearGradient>
              </defs>
              <CartesianGrid strokeDasharray="3 3" stroke="#edf0f7" />
              <XAxis dataKey="date" tick={{ fontSize: 12 }} tickLine={false} axisLine={{ stroke: '#edf0f7' }} />
              <YAxis allowDecimals={false} tick={{ fontSize: 12 }} tickLine={false} axisLine={false} />
              <Tooltip
                contentStyle={{ borderRadius: 12, border: '1px solid #edf0f7', boxShadow: '0 8px 24px rgba(0,0,0,0.08)' }}
              />
              <Area
                type="monotone"
                dataKey={dataKey}
                name={name}
                stroke={color}
                strokeWidth={2.5}
                fill={`url(#${gradientId})`}
                dot={{ r: 3, fill: color }}
                activeDot={{ r: 5 }}
              />
            </AreaChart>
          </ResponsiveContainer>
        </Box>
      </CardContent>
    </Card>
  )
}

export default function DashboardPage() {
  const [summary, setSummary] = useState(null)
  const [trends, setTrends] = useState([])

  const refresh = useCallback(async () => {
    const [s, t] = await Promise.all([getDashboardSummary(), getDashboardTrends(7)])
    setSummary(s)
    setTrends(t)
  }, [])

  useEffect(() => {
    refresh().catch(() => {})
    const unsubscribe = subscribeAdminDashboard(() => {
      refresh().catch(() => {})
    })
    return unsubscribe
  }, [refresh])

  const cards = [
    { icon: <MeetingRoomIcon />, label: '全部房间', value: summary?.totalRooms, color: '#3f51e0' },
    { icon: <HourglassTopIcon />, label: '等待中', value: summary?.waitingRooms, color: '#fb8c00' },
    { icon: <PlayCircleIcon />, label: '运行中', value: summary?.runningRooms, color: '#00bfa5' },
    { icon: <DoorFrontIcon />, label: '已结束', value: summary?.closedRooms, color: '#78909c' },
    { icon: <WarningAmberIcon />, label: '红灯预警', value: summary?.alertRooms, color: '#e53935' },
    { icon: <FavoriteIcon />, label: '今日点赞', value: summary?.todayLikes, color: '#ec407a' },
    { icon: <FavoriteBorderIcon />, label: '累计点赞', value: summary?.totalLikes, color: '#ab47bc' },
    { icon: <ScheduleIcon />, label: '待执行计划', value: summary?.pendingSchedules, color: '#8e24aa' },
  ]

  return (
    <Box>
      <Typography variant="h5" sx={{ mb: 3 }}>仪表盘</Typography>
      <Grid container spacing={2.5} sx={{ mb: 3 }}>
        {cards.map((card) => (
          <Grid item xs={12} sm={6} md={3} key={card.label}>
            <StatCard icon={card.icon} label={card.label} value={card.value ?? '-'} color={card.color} />
          </Grid>
        ))}
      </Grid>

      <Grid container spacing={2.5}>
        <Grid item xs={12} md={6}>
          <TrendChart
            title="近 7 日点赞趋势"
            data={trends}
            dataKey="likes"
            name="点赞数"
            color="#ec407a"
          />
        </Grid>
        <Grid item xs={12} md={6}>
          <TrendChart
            title="近 7 日新建房间趋势"
            data={trends}
            dataKey="rooms"
            name="新建房间"
            color="#3f51e0"
          />
        </Grid>
      </Grid>
    </Box>
  )
}
