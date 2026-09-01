import { useCallback, useEffect, useRef, useState } from 'react'
import {
  Alert, Box, Card, CardContent, Chip, Grid, IconButton, Skeleton, Stack, ToggleButton,
  ToggleButtonGroup, Tooltip as MuiTooltip, Typography,
} from '@mui/material'
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
import RefreshIcon from '@mui/icons-material/Refresh'
import { getDashboardSummary, getDashboardTrends } from '../api'
import { subscribeAdminDashboard } from '../api/ws'
import PageHeader from '../components/PageHeader'
import EmptyState from '../components/EmptyState'

const TREND_RANGES = [7, 14, 30]
const REFRESH_DEBOUNCE_MS = 800

function StatCard({ icon, label, value, color, loading }) {
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
            width: 52, height: 52, borderRadius: 3, display: 'flex', flexShrink: 0,
            alignItems: 'center', justifyContent: 'center',
            background: `linear-gradient(135deg, ${color}26, ${color}12)`, color,
          }}
        >
          {icon}
        </Box>
        <Box sx={{ minWidth: 0 }}>
          {loading ? (
            <Skeleton variant="text" width={64} height={36} />
          ) : (
            <Typography variant="h5" sx={{ fontVariantNumeric: 'tabular-nums' }}>{value}</Typography>
          )}
          <Typography variant="body2" color="text.secondary" noWrap>{label}</Typography>
        </Box>
      </CardContent>
    </Card>
  )
}

function TrendChart({ title, data, dataKey, name, color, loading }) {
  const gradientId = `grad-${dataKey}`
  const total = data.reduce((sum, item) => sum + (Number(item[dataKey]) || 0), 0)
  return (
    <Card sx={{ height: '100%' }}>
      <CardContent>
        <Stack direction="row" alignItems="center" justifyContent="space-between" sx={{ mb: 2 }}>
          <Typography variant="h6">{title}</Typography>
          {!loading && (
            <Chip size="small" label={`合计 ${total}`} sx={{ bgcolor: `${color}1a`, color, fontWeight: 700 }} />
          )}
        </Stack>
        <Box sx={{ height: 300 }}>
          {loading ? (
            <Skeleton variant="rounded" width="100%" height="100%" />
          ) : data.length === 0 ? (
            <EmptyState compact title="暂无趋势数据" description="有房间创建或点赞后将在此展示" />
          ) : (
            <ResponsiveContainer width="100%" height="100%">
              <AreaChart data={data} margin={{ top: 8, right: 16, left: -12, bottom: 0 }}>
                <defs>
                  <linearGradient id={gradientId} x1="0" y1="0" x2="0" y2="1">
                    <stop offset="5%" stopColor={color} stopOpacity={0.35} />
                    <stop offset="95%" stopColor={color} stopOpacity={0.02} />
                  </linearGradient>
                </defs>
                <CartesianGrid strokeDasharray="3 3" stroke="#edf0f7" vertical={false} />
                <XAxis dataKey="date" tick={{ fontSize: 12 }} tickLine={false} axisLine={{ stroke: '#edf0f7' }} minTickGap={16} />
                <YAxis allowDecimals={false} tick={{ fontSize: 12 }} tickLine={false} axisLine={false} />
                <Tooltip
                  contentStyle={{ borderRadius: 12, border: '1px solid #edf0f7', boxShadow: '0 8px 24px rgba(0,0,0,0.08)' }}
                  cursor={{ stroke: color, strokeOpacity: 0.3 }}
                />
                <Area
                  type="monotone"
                  dataKey={dataKey}
                  name={name}
                  stroke={color}
                  strokeWidth={2.5}
                  fill={`url(#${gradientId})`}
                  dot={data.length <= 14 ? { r: 3, fill: color } : false}
                  activeDot={{ r: 5 }}
                  isAnimationActive={false}
                />
              </AreaChart>
            </ResponsiveContainer>
          )}
        </Box>
      </CardContent>
    </Card>
  )
}

export default function DashboardPage() {
  const [summary, setSummary] = useState(null)
  const [trends, setTrends] = useState([])
  const [days, setDays] = useState(7)
  const [loading, setLoading] = useState(true)
  const [refreshing, setRefreshing] = useState(false)
  const [error, setError] = useState('')
  const [updatedAt, setUpdatedAt] = useState(null)
  const debounceRef = useRef(null)

  const refresh = useCallback(async (silent = false) => {
    if (!silent) setRefreshing(true)
    try {
      const [s, t] = await Promise.all([getDashboardSummary(), getDashboardTrends(days)])
      setSummary(s)
      setTrends(Array.isArray(t) ? t : [])
      setError('')
      setUpdatedAt(new Date())
    } catch (err) {
      setError(err.message || '加载仪表盘数据失败')
    } finally {
      setLoading(false)
      setRefreshing(false)
    }
  }, [days])

  useEffect(() => {
    refresh()
  }, [refresh])

  useEffect(() => {
    // 看板事件很密集(成员进出/点赞), 合并短时间内的多次刷新
    const unsubscribe = subscribeAdminDashboard(() => {
      clearTimeout(debounceRef.current)
      debounceRef.current = setTimeout(() => refresh(true), REFRESH_DEBOUNCE_MS)
    })
    return () => {
      clearTimeout(debounceRef.current)
      unsubscribe()
    }
  }, [refresh])

  const cards = [
    { icon: <MeetingRoomIcon />, label: '全部房间', value: summary?.totalRooms, color: '#3f51e0' },
    { icon: <HourglassTopIcon />, label: '等待中', value: summary?.waitingRooms, color: '#fb8c00' },
    { icon: <PlayCircleIcon />, label: '运行中', value: summary?.runningRooms, color: '#00bfa5' },
    { icon: <DoorFrontIcon />, label: '已结束', value: summary?.closedRooms, color: '#78909c' },
    { icon: <WarningAmberIcon />, label: '红灯预警', value: summary?.alertRooms, color: '#e53935' },
    { icon: <FavoriteIcon />, label: '今日点赞', value: summary?.todayLikes, color: '#ec407a' },
    { icon: <FavoriteBorderIcon />, label: '累计点赞', value: summary?.totalLikes, color: '#ab47bc' },
  ]

  return (
    <Box>
      <PageHeader
        title="仪表盘"
        subtitle={updatedAt ? `实时看板 · 更新于 ${updatedAt.toLocaleTimeString('zh-CN', { hour12: false })}` : '实时看板'}
        actions={(
          <MuiTooltip title="刷新">
            <IconButton onClick={() => refresh()} disabled={refreshing} aria-label="刷新">
              <RefreshIcon sx={refreshing ? { animation: 'spin 1s linear infinite', '@keyframes spin': { to: { transform: 'rotate(360deg)' } } } : undefined} />
            </IconButton>
          </MuiTooltip>
        )}
      />

      {error && (
        <Alert severity="error" sx={{ mb: 2 }} onClose={() => setError('')}>
          {error}
        </Alert>
      )}

      <Grid container spacing={2.5} sx={{ mb: 3 }}>
        {cards.map((card) => (
          <Grid item xs={12} sm={6} md={4} lg={3} key={card.label}>
            <StatCard
              icon={card.icon}
              label={card.label}
              value={card.value ?? '-'}
              color={card.color}
              loading={loading}
            />
          </Grid>
        ))}
      </Grid>

      <Stack direction="row" alignItems="center" justifyContent="space-between" sx={{ mb: 1.5 }}>
        <Typography variant="subtitle1" sx={{ fontWeight: 700 }}>趋势</Typography>
        <ToggleButtonGroup
          size="small"
          exclusive
          value={days}
          onChange={(e, value) => value && setDays(value)}
          aria-label="趋势天数"
        >
          {TREND_RANGES.map((range) => (
            <ToggleButton key={range} value={range} sx={{ px: 1.5 }}>近 {range} 日</ToggleButton>
          ))}
        </ToggleButtonGroup>
      </Stack>

      <Grid container spacing={2.5}>
        <Grid item xs={12} md={6}>
          <TrendChart
            title="点赞趋势"
            data={trends}
            dataKey="likes"
            name="点赞数"
            color="#ec407a"
            loading={loading}
          />
        </Grid>
        <Grid item xs={12} md={6}>
          <TrendChart
            title="新建房间趋势"
            data={trends}
            dataKey="rooms"
            name="新建房间"
            color="#3f51e0"
            loading={loading}
          />
        </Grid>
      </Grid>
    </Box>
  )
}
