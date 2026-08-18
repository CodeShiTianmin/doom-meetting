import { useEffect, useState } from 'react'
import { useNavigate, useSearchParams } from 'react-router-dom'
import {
  Alert, Box, Button, Card, CardContent, CircularProgress, TextField, Typography,
} from '@mui/material'
import CastConnectedIcon from '@mui/icons-material/CastConnected'
import { joinRoom } from '../api/client'

/**
 * 入会页: 扫码进入(URL 携带 room/token)或手动输入房号与凭证
 */
export default function JoinPage() {
  const navigate = useNavigate()
  const [params] = useSearchParams()
  const [roomCode, setRoomCode] = useState(params.get('room') || '')
  const [inviteToken, setInviteToken] = useState(params.get('token') || '')
  const [nickname, setNickname] = useState('')
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(false)

  useEffect(() => {
    setRoomCode(params.get('room') || '')
    setInviteToken(params.get('token') || '')
  }, [params])

  const submit = async (e) => {
    e.preventDefault()
    setError('')
    setLoading(true)
    try {
      const data = await joinRoom({
        roomCode: roomCode.trim(),
        inviteToken: inviteToken.trim(),
        nickname: nickname.trim(),
        deviceInfo: navigator.userAgent.slice(0, 120),
      })
      sessionStorage.setItem('meeting_session', JSON.stringify(data))
      navigate('/room')
    } catch (err) {
      setError(err.message)
    } finally {
      setLoading(false)
    }
  }

  return (
    <Box
      sx={{
        minHeight: '100vh', display: 'flex', alignItems: 'center',
        justifyContent: 'center', p: 2,
        background: 'linear-gradient(160deg, #0d1030 0%, #1b2260 60%, #2c3aa8 100%)',
      }}
    >
      <Card sx={{ width: '100%', maxWidth: 400 }}>
        <CardContent sx={{ p: 3 }}>
          <Box sx={{ textAlign: 'center', mb: 3 }}>
            <CastConnectedIcon sx={{ fontSize: 46, color: 'primary.main' }} />
            <Typography variant="h5" sx={{ mt: 1, fontWeight: 700 }}>
              投屏会议
            </Typography>
            <Typography variant="body2" color="text.secondary">
              扫码或输入房号加入会议(每房间限 2 位客户)
            </Typography>
          </Box>
          {error && <Alert severity="error" sx={{ mb: 2 }}>{error}</Alert>}
          <form onSubmit={submit}>
            <TextField
              fullWidth
              label="房号"
              value={roomCode}
              onChange={(e) => setRoomCode(e.target.value)}
              sx={{ mb: 2 }}
            />
            <TextField
              fullWidth
              label="入会凭证"
              value={inviteToken}
              onChange={(e) => setInviteToken(e.target.value)}
              sx={{ mb: 2 }}
            />
            <TextField
              fullWidth
              label="您的昵称"
              value={nickname}
              onChange={(e) => setNickname(e.target.value)}
              sx={{ mb: 3 }}
            />
            <Button
              fullWidth
              size="large"
              type="submit"
              variant="contained"
              disabled={loading || !roomCode || !inviteToken || !nickname}
            >
              {loading ? <CircularProgress size={24} color="inherit" /> : '加入会议'}
            </Button>
          </form>
          <Typography variant="caption" color="text.secondary" sx={{ display: 'block', mt: 2, textAlign: 'center' }}>
            会议内容仅限实时观看 · 可截屏 · 禁止录制
          </Typography>
        </CardContent>
      </Card>
    </Box>
  )
}
