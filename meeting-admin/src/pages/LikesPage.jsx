import { useEffect, useMemo, useState } from 'react'
import {
  Alert, Box, Card, CardContent, Chip, Grid, InputAdornment, MenuItem,
  Table, TableBody, TableCell, TableHead, TablePagination, TableRow,
  TextField, Typography,
} from '@mui/material'
import SearchIcon from '@mui/icons-material/Search'
import FavoriteIcon from '@mui/icons-material/Favorite'
import MeetingRoomIcon from '@mui/icons-material/MeetingRoom'
import PeopleIcon from '@mui/icons-material/People'
import TodayIcon from '@mui/icons-material/Today'
import { listAllLikes } from '../api'

function SummaryCard({ icon, label, value, color }) {
  return (
    <Card sx={{ height: '100%' }}>
      <CardContent sx={{ display: 'flex', alignItems: 'center', gap: 2 }}>
        <Box
          sx={{
            width: 44, height: 44, borderRadius: 2.5, display: 'flex',
            alignItems: 'center', justifyContent: 'center',
            background: `linear-gradient(135deg, ${color}26, ${color}12)`, color,
          }}
        >
          {icon}
        </Box>
        <Box>
          <Typography variant="h6" sx={{ fontVariantNumeric: 'tabular-nums' }}>{value}</Typography>
          <Typography variant="body2" color="text.secondary">{label}</Typography>
        </Box>
      </CardContent>
    </Card>
  )
}

export default function LikesPage() {
  const [likes, setLikes] = useState([])
  const [error, setError] = useState('')
  const [keyword, setKeyword] = useState('')
  const [roomFilter, setRoomFilter] = useState('ALL')
  const [dateFrom, setDateFrom] = useState('')
  const [dateTo, setDateTo] = useState('')
  const [page, setPage] = useState(0)
  const [rowsPerPage, setRowsPerPage] = useState(10)

  useEffect(() => {
    listAllLikes()
      .then(setLikes)
      .catch((err) => setError(err.message))
  }, [])

  const roomOptions = useMemo(() => {
    const map = new Map()
    likes.forEach((like) => {
      if (!map.has(like.roomCode)) map.set(like.roomCode, like.roomName)
    })
    return [...map.entries()].map(([code, name]) => ({ code, name }))
  }, [likes])

  const filtered = useMemo(() => {
    const kw = keyword.trim().toLowerCase()
    return likes.filter((like) => {
      if (roomFilter !== 'ALL' && like.roomCode !== roomFilter) return false
      if (dateFrom && like.likedAt < `${dateFrom}T00:00:00`) return false
      if (dateTo && like.likedAt > `${dateTo}T23:59:59`) return false
      if (!kw) return true
      return [like.nickname, like.memberIdentity, like.roomName, like.roomCode]
        .some((field) => (field || '').toLowerCase().includes(kw))
    })
  }, [likes, keyword, roomFilter, dateFrom, dateTo])

  const todayPrefix = new Date().toISOString().slice(0, 10)
  const todayCount = likes.filter((like) => (like.likedAt || '').startsWith(todayPrefix)).length
  const uniqueUsers = new Set(likes.map((like) => like.memberIdentity || like.nickname)).size

  const paged = filtered.slice(page * rowsPerPage, page * rowsPerPage + rowsPerPage)

  const resetPage = () => setPage(0)

  return (
    <Box>
      <Typography variant="h5" sx={{ mb: 3 }}>点赞记录</Typography>
      {error && <Alert severity="error" sx={{ mb: 2 }} onClose={() => setError('')}>{error}</Alert>}

      <Grid container spacing={2.5} sx={{ mb: 3 }}>
        <Grid item xs={12} sm={6} md={3}>
          <SummaryCard icon={<FavoriteIcon />} label="累计点赞" value={likes.length} color="#ec407a" />
        </Grid>
        <Grid item xs={12} sm={6} md={3}>
          <SummaryCard icon={<TodayIcon />} label="今日点赞" value={todayCount} color="#fb8c00" />
        </Grid>
        <Grid item xs={12} sm={6} md={3}>
          <SummaryCard icon={<MeetingRoomIcon />} label="涉及房间" value={roomOptions.length} color="#3f51e0" />
        </Grid>
        <Grid item xs={12} sm={6} md={3}>
          <SummaryCard icon={<PeopleIcon />} label="点赞用户" value={uniqueUsers} color="#00bfa5" />
        </Grid>
      </Grid>

      <Card>
        <CardContent>
          <Box sx={{ display: 'flex', gap: 2, flexWrap: 'wrap', mb: 2 }}>
            <TextField
              size="small"
              placeholder="搜索昵称 / 身份 / 房间"
              value={keyword}
              onChange={(e) => { setKeyword(e.target.value); resetPage() }}
              sx={{ minWidth: 260 }}
              InputProps={{
                startAdornment: (
                  <InputAdornment position="start">
                    <SearchIcon fontSize="small" />
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
              onChange={(e) => { setDateFrom(e.target.value); resetPage() }}
            />
            <TextField
              size="small"
              type="date"
              label="结束日期"
              InputLabelProps={{ shrink: true }}
              value={dateTo}
              onChange={(e) => { setDateTo(e.target.value); resetPage() }}
            />
            <Box sx={{ flexGrow: 1 }} />
            <Chip label={`筛选结果 ${filtered.length} 条`} color="primary" variant="outlined" />
          </Box>

          <Table>
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
                    <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                      <FavoriteIcon sx={{ fontSize: 16, color: '#ec407a' }} />
                      {like.nickname || '匿名用户'}
                    </Box>
                  </TableCell>
                  <TableCell>
                    <Typography variant="body2" color="text.secondary">
                      {like.memberIdentity || '-'}
                    </Typography>
                  </TableCell>
                  <TableCell>
                    <Chip size="small" label={`${like.roomName}（${like.roomCode}）`} variant="outlined" />
                  </TableCell>
                  <TableCell>{like.likedAt?.replace('T', ' ')}</TableCell>
                </TableRow>
              ))}
              {paged.length === 0 && (
                <TableRow>
                  <TableCell colSpan={4}>
                    <Typography color="text.secondary" align="center" sx={{ py: 4 }}>
                      暂无匹配的点赞记录
                    </Typography>
                  </TableCell>
                </TableRow>
              )}
            </TableBody>
          </Table>
          <TablePagination
            component="div"
            count={filtered.length}
            page={page}
            onPageChange={(_, newPage) => setPage(newPage)}
            rowsPerPage={rowsPerPage}
            onRowsPerPageChange={(e) => { setRowsPerPage(parseInt(e.target.value, 10)); resetPage() }}
            rowsPerPageOptions={[10, 20, 50]}
            labelRowsPerPage="每页条数"
            labelDisplayedRows={({ from, to, count }) => `第 ${from}-${to} 条 / 共 ${count} 条`}
          />
        </CardContent>
      </Card>
    </Box>
  )
}
