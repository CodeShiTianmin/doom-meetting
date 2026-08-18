import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import {
  Alert, Box, Button, Card, CardContent, CircularProgress, InputAdornment,
  TextField, Typography,
} from '@mui/material'
import PersonIcon from '@mui/icons-material/Person'
import LockIcon from '@mui/icons-material/Lock'
import CastConnectedIcon from '@mui/icons-material/CastConnected'
import { login } from '../api'

export default function LoginPage() {
  const navigate = useNavigate()
  const [username, setUsername] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(false)

  const submit = async (e) => {
    e.preventDefault()
    setError('')
    setLoading(true)
    try {
      const data = await login(username, password)
      localStorage.setItem('admin_token', data.token)
      localStorage.setItem('admin_name', data.displayName || data.username)
      navigate('/dashboard')
    } catch (err) {
      setError(err.message)
    } finally {
      setLoading(false)
    }
  }

  return (
    <Box
      sx={{
        minHeight: '100vh',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        background: 'linear-gradient(135deg, #2c3aa8 0%, #3f51e0 45%, #7986f5 100%)',
      }}
    >
      <Card sx={{ width: 400, mx: 2 }}>
        <CardContent sx={{ p: 4 }}>
          <Box sx={{ textAlign: 'center', mb: 3 }}>
            <CastConnectedIcon sx={{ fontSize: 48, color: 'primary.main' }} />
            <Typography variant="h5" sx={{ mt: 1 }}>
              多房并发投屏会议
            </Typography>
            <Typography variant="body2" color="text.secondary">
              公司 PC 管理端 · 后台隐藏身份
            </Typography>
          </Box>
          {error && (
            <Alert severity="error" sx={{ mb: 2 }}>
              {error}
            </Alert>
          )}
          <form onSubmit={submit}>
            <TextField
              fullWidth
              label="账号"
              value={username}
              onChange={(e) => setUsername(e.target.value)}
              sx={{ mb: 2 }}
              InputProps={{
                startAdornment: (
                  <InputAdornment position="start">
                    <PersonIcon color="action" />
                  </InputAdornment>
                ),
              }}
            />
            <TextField
              fullWidth
              type="password"
              label="密码"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              sx={{ mb: 3 }}
              InputProps={{
                startAdornment: (
                  <InputAdornment position="start">
                    <LockIcon color="action" />
                  </InputAdornment>
                ),
              }}
            />
            <Button
              fullWidth
              size="large"
              type="submit"
              variant="contained"
              disabled={loading || !username || !password}
            >
              {loading ? <CircularProgress size={24} color="inherit" /> : '登 录'}
            </Button>
          </form>
        </CardContent>
      </Card>
    </Box>
  )
}
