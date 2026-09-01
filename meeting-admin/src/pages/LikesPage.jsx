import { useCallback, useEffect, useMemo, useState } from 'react'
import {
  Alert, Box, Button, Card, CardContent, Chip, CircularProgress, Grid, IconButton,
  InputAdornment, MenuItem, Skeleton, Stack, Table, TableBody, TableCell, TableContainer,
  TableHead, TablePagination, TableRow, TextField, Tooltip, Typography,
} from '@mui/material'
import SearchIcon from '@mui/icons-material/Search'
import FavoriteIcon from '@mui/icons-material/Favorite'
import MeetingRoomIcon from '@mui/icons-material/MeetingRoom'
import PeopleIcon from '@mui/icons-material/People'
import TodayIcon from '@mui/icons-material/Today'
import RefreshIcon from '@mui/icons-material/Refresh'
import FilterAltOffIcon from '@mui/icons-material/FilterAltOff'
import { listAllLikes } from '../api'
import PageHeader from '../components/PageHeader.jsx'
import EmptyState from '../components/EmptyState.jsx'

function localDateString(date = new Date()) {
  const y = date.getFullYear()
  const m = String(date.getMonth() + 1).padStart(2, '0')
  const d = String(date.getDate()).padStart(2, '0')
  return `${y}-${m}-${d}`
}

function SummaryCard({ icon, label, value, color, loading }) {
  return (
    <Card sx={{ height: '100%' }}>
      <CardContent sx={{ display: 'flex', alignItems: 'center', gap: 2 }}>
        <Box
          sx={{
            width: 44, height: 44, borderRadius: 2.5, display: 'flex', flexShrink: 0,
            alignItems: 'center', justifyContent: 'center',
            background: `linear-gradient(135deg, ${color}26, ${color}12)`, color,
          }}
        >
          {icon}
        </Box>
        <Box sx={{ minWidth: 0 }}>
          {loading ? (
            <Skeleton variant="text" width={56} height={32} />
          ) : (
            <Typography variant="h6" sx={{ fontVariantNumeric: 'tabular-nums' }}>{value}</Typography>
          )}
          <Typography variant="body2" color="text.secondary" noWrap>{label}</Typography>
        </Box>
      </CardContent>
    </Card>
  )
}

export default function LikesPage() {
  const [likes, setLikes] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [keyword, setKeyword] = useState('')
  const [roomFilter, setRoomFilter] = useState('ALL')
  const [dateFrom, setDateFrom] = useState('')
  const [dateTo, setDateTo] = useState('')
  const [page, setPage] = useState(0)
  const [rowsPerPage, setRowsPerPage] = useState(10)

  const load = useCallback(async () => {
    setLoading(true)
    try {
      const list = await listAllLikes()
      setLikes(Array.isArray(list) ? list : [])
      setError('')
    } catch (err) {
      setError(err.message || '加载点赞记录失败')
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    load()
  }, [load])

  const roomOptions = useMemo(() => {
    const map = new Map()
    likes.forEach((like) => {
      if (like.roomCode && !map.has(like.roomCode)) map.set(like.roomCode, like.roomName)
    })
    return [...map.entries()].map(([code, name]) => ({ code, name }))
  }, [likes])

  const filtered = useMemo(() => {
    const kw = keyword.trim().toLowerCase()
    return likes.filter((like) => {
      if (roomFilter !== 'ALL' && like.roomCode !== roomFilter) return false
      const day = (like.likedAt || '').slice(0, 10)
      if (dateFrom && day < dateFrom) return false
      if (dateTo && day > dateTo) return false
      if (!kw) return true
      return [like.nickname, like.memberIdentity, like.roomName, like.roomCode]
        .some((field) => (field || '').toLowerCase().includes(kw))
    })
  }, [likes, keyword, roomFilter, dateFrom, dateTo])

  const todayPrefix = localDateString()
  const todayCount = useMemo(
    () => likes.filter((like) => (like.likedAt || '').startsWith(todayPrefix)).length,
    [likes, todayPrefix],
  )
  const uniqueUsers = useMemo(
    () => new Set(likes.map((like) => like.memberIdentity || like.nickname).filter(Boolean)).size,
    [likes],
  )

  const pageCount = Math.max(0, Math.ceil(filtered.length / rowsPerPage) - 1)
  const safePage = Math.min(page, pageCount)
  const paged = filtered.slice(safePage * rowsPerPage, safePage * rowsPerPage + rowsPerPage)

  const hasFilter = Boolean(keyword.trim() || roomFilter !== 'ALL' || dateFrom || dateTo)
  const dateRangeInvalid = Boolean(dateFrom && dateTo && dateFrom > dateTo)

  const resetPage = () => setPage(0)
  const clearFilters = () => {
    setKeyword('')
    setRoomFilter('ALL')
    setDateFrom('')
    setDateTo('')
    resetPage()
  }

  return (
    <Box>
      <PageHeader
        title="点赞记录"
        subtitle="手机端观众点赞明细, 支持按房间与日期筛选"
        actions={(
          <Tooltip title="刷新">
            <IconButton onClick={load} disabled={loading} aria-label="刷新">
              <RefreshIcon />
            </IconButton>
          </Tooltip>
        )}
      />
      {error && (
        <Alert
          severity="error"
          sx={{ mb: 2 }}
          onClose={() => setError('')}
          action={<Button color="inherit" size="small" onClick={load}>重试</Button>}
        >
          {error}
        </Alert>
      )}

      <Grid container spacing={2.5} sx={{ mb: 3 }}>
        <Grid item xs={12} sm={6} md={3}>
          <SummaryCard icon={<FavoriteIcon />} label="累计点赞" value={likes.length} color="#ec407a" loading={loading} />
        </Grid>
        <Grid item xs={12} sm={6} md={3}>
          <SummaryCard icon={<TodayIcon />} label="今日点赞" value={todayCount} color="#fb8c00" loading={loading} />
        </Grid>
        <Grid item xs={12} sm={6} md={3}>
          <SummaryCard icon={<MeetingRoomIcon />} label="涉及房间" value={roomOptions.length} color="#3f51e0" loading={loading} />
        </Grid>
        <Grid item xs={12} sm={6} md={3}>
          <SummaryCard icon={<PeopleIcon />} label="点赞用户" value={uniqueUsers} color="#00bfa5" loading={loading} />
        </Grid>
      </Grid>

      <Card>
        <CardContent>
          <Stack direction="row" spacing={2} flexWrap="wrap" useFlexGap alignItems="center" sx={{ mb: 2 }}>
            <TextField
              size="small"
              placeholder="搜索昵称 / 身份 / 房间"
              value={keyword}
              onChange={(e) => { setKeyword(e.target.value); resetPage() }}
              sx={{ minWidth: { xs: '100%', sm: 240 }, flexGrow: { xs: 1, md: 0 } }}
              InputProps={{
                startAdornment: (
                  <InputAdornment position="start">
                    <SearchIcon fontSize="small" color="action" />
                  </InputAdornment>
                ),
              }}
            />
            <TextField
              size="small"
              select
              label="房间"
              value={roomFilter}
              onChange={(e) => { setRoomFilter(e.target.value); resetPage() }}
              sx={{ minWidth: 180 }}
            >
              <MenuItem value="ALL">全部房间</MenuItem>
              {roomOptions.map((room) => (
                <MenuItem key={room.code} value={room.code}>
                  {room.name}（{room.code}）
                </MenuItem>
              ))}
            </TextField>
            <TextField
              size="small"
              type="date"
              label="开始日期"
              InputLabelProps={{ shrink: true }}
              value={dateFrom}
              error={dateRangeInvalid}
              inputProps={{ max: dateTo || undefined }}
              onChange={(e) => { setDateFrom(e.target.value); resetPage() }}
            />
            <TextField
              size="small"
              type="date"
              label="结束日期"
              InputLabelProps={{ shrink: true }}
              value={dateTo}
              error={dateRangeInvalid}
              helperText={dateRangeInvalid ? '结束日期早于开始日期' : undefined}
              inputProps={{ min: dateFrom || undefined }}
              onChange={(e) => { setDateTo(e.target.value); resetPage() }}
            />
            <Box sx={{ flexGrow: 1 }} />
            {hasFilter && (
              <Button size="small" startIcon={<FilterAltOffIcon />} onClick={clearFilters}>清除筛选</Button>
            )}
            <Chip label={`筛选结果 ${filtered.length} 条`} color="primary" variant="outlined" />
          </Stack>

          {loading ? (
            <Box sx={{ py: 6, display: 'flex', justifyContent: 'center' }}>
              <CircularProgress />
            </Box>
          ) : filtered.length === 0 ? (
            <EmptyState
              icon={FavoriteIcon}
              title={hasFilter ? '没有匹配的点赞记录' : '暂无点赞记录'}
              description={hasFilter ? '调整筛选条件后再试' : '观众在手机端点赞后会实时记录在此'}
              action={hasFilter && <Button variant="outlined" size="small" onClick={clearFilters}>清除筛选</Button>}
            />
          ) : (
            <>
              <TableContainer>
                <Table sx={{ minWidth: 640 }}>
                  <TableHead>
                    <TableRow>
                      <TableCell>用户昵称</TableCell>
                      <TableCell>身份标识</TableCell>
                      <TableCell>房间</TableCell>
                      <TableCell>点赞时间</TableCell>
                    </TableRow>
                  </TableHead>
                  <TableBody>
                    {paged.map((like) => (
                      <TableRow key={like.id} hover>
                        <TableCell>
                          <Stack direction="row" alignItems="center" spacing={1}>
                            <FavoriteIcon sx={{ fontSize: 16, color: '#ec407a' }} />
                            <Typography variant="body2" sx={{ fontWeight: 600 }}>{like.nickname || '匿名用户'}</Typography>
                          </Stack>
                        </TableCell>
                        <TableCell>
                          <Typography variant="body2" color="text.secondary" sx={{ fontFamily: 'monospace' }}>
                            {like.memberIdentity || '-'}
                          </Typography>
                        </TableCell>
                        <TableCell>
                          <Chip size="small" label={`${like.roomName || '-'}（${like.roomCode || '-'}）`} variant="outlined" />
                        </TableCell>
                        <TableCell sx={{ whiteSpace: 'nowrap', color: 'text.secondary' }}>
                          {like.likedAt?.replace('T', ' ').slice(0, 19)}
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              </TableContainer>
              <TablePagination
                component="div"
                count={filtered.length}
                page={safePage}
                onPageChange={(_, newPage) => setPage(newPage)}
                rowsPerPage={rowsPerPage}
                onRowsPerPageChange={(e) => { setRowsPerPage(parseInt(e.target.value, 10)); resetPage() }}
                rowsPerPageOptions={[10, 20, 50]}
                labelRowsPerPage="每页条数"
                labelDisplayedRows={({ from, to, count }) => `第 ${from}-${to} 条 / 共 ${count} 条`}
              />
            </>
          )}
        </CardContent>
      </Card>
    </Box>
  )
}
