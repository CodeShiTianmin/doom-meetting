import { useCallback, useEffect, useState } from 'react'
import {
  Alert, Box, Card, CardContent, Table, TableBody, TableCell, TableHead,
  TableRow, Typography,
} from '@mui/material'
import FavoriteIcon from '@mui/icons-material/Favorite'
import { listAllLikes } from '../api'
import { subscribeAdminDashboard } from '../api/ws'

export default function LikesPage() {
  const [likes, setLikes] = useState([])
  const [error, setError] = useState('')

  const refresh = useCallback(async () => {
    setLikes(await listAllLikes())
  }, [])

  useEffect(() => {
    refresh().catch((err) => setError(err.message))
    const unsubscribe = subscribeAdminDashboard((event) => {
      if (event.type === 'LIKE') refresh().catch(() => {})
    })
    return unsubscribe
  }, [refresh])

  return (
    <Box>
      <Typography variant="h5" sx={{ mb: 3 }}>
        <FavoriteIcon sx={{ verticalAlign: 'middle', mr: 1, color: '#ec407a' }} />
        点赞记录
      </Typography>
      {error && <Alert severity="error" sx={{ mb: 2 }} onClose={() => setError('')}>{error}</Alert>}
      <Card>
        <CardContent>
          <Table>
            <TableHead>
              <TableRow>
                <TableCell>房间</TableCell>
                <TableCell>房号</TableCell>
                <TableCell>客户昵称</TableCell>
                <TableCell>点赞时间</TableCell>
              </TableRow>
            </TableHead>
            <TableBody>
              {likes.map((like) => (
                <TableRow key={like.id} hover>
                  <TableCell>{like.roomName}</TableCell>
                  <TableCell>{like.roomCode}</TableCell>
                  <TableCell>{like.nickname}</TableCell>
                  <TableCell>{like.likedAt?.replace('T', ' ')}</TableCell>
                </TableRow>
              ))}
              {likes.length === 0 && (
                <TableRow>
                  <TableCell colSpan={4}>
                    <Typography color="text.secondary" align="center" sx={{ py: 3 }}>
                      暂无点赞记录
                    </Typography>
                  </TableCell>
                </TableRow>
              )}
            </TableBody>
          </Table>
        </CardContent>
      </Card>
    </Box>
  )
}
