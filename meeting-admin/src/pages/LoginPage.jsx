import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import {
  Alert, Box, Button, Card, CardContent, CircularProgress, IconButton, InputAdornment,
  Stack, TextField, Typography,
} from '@mui/material'
import PersonIcon from '@mui/icons-material/Person'
import LockIcon from '@mui/icons-material/Lock'
import Visibility from '@mui/icons-material/Visibility'
import VisibilityOff from '@mui/icons-material/VisibilityOff'
import CastConnectedIcon from '@mui/icons-material/CastConnected'
import { login } from '../api'

const FEATURES = ['20 房并发投屏', '全员就位自动开会', '缺人红灯预警', '录屏检测 · 水印保护']

export default function LoginPage() {
  const navigate = useNavigate()
  const [username, setUsername] = useState('')
  const [password, setPassword] = useState('')
  const [showPassword, setShowPassword] = useState(false)
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(false)

  const submit = async (e) => {
    e.preventDefault()
    if (loading) return
    const name = username.trim()
    if (!name || !password) return
    setError('')
    setLoading(true)
    try {
      const data = await login(name, password)
      localStorage.setItem('admin_token', data.token)
      localStorage.setItem('admin_name', data.displayName || data.username)
      localStorage.setItem('admin_username', data.username)
      navigate('/dashboard', { replace: true })
    } catch (err) {
      setError(err.message || '登录失败, 请稍后重试')
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
        position: 'relative',
        overflow: 'hidden',
        background: 'linear-gradient(135deg, #1e1b4b 0%, #4f46e5 50%, #8b7ff8 100%)',
        '&::before, &::after': {
          content: '""',
          position: 'absolute',
          borderRadius: '50%',
          filter: 'blur(60px)',
          opacity: 0.55,
          pointerEvents: 'none',
        },
        '&::before': {
          width: 420, height: 420, top: -120, left: -120,
          background: 'radial-gradient(circle, #06b6a4 0%, transparent 70%)',
        },
        '&::after': {
          width: 520, height: 520, bottom: -200, right: -160,
          background: 'radial-gradient(circle, #f472b6 0%, transparent 70%)',
        },
      }}
    >
      <Stack
        direction={{ xs: 'column', md: 'row' }}
        spacing={{ xs: 4, md: 8 }}
        alignItems="center"
        sx={{ position: 'relative', zIndex: 1, px: 2, py: 4, width: '100%', maxWidth: 960 }}
      >
        <Box sx={{ flex: 1, color: '#fff', display: { xs: 'none', md: 'block' } }}>
          <Typography variant="overline" sx={{ letterSpacing: 3, opacity: 0.8 }}>
            DOOM MEETING
          </Typography>
          <Typography variant="h3" sx={{ fontWeight: 800, lineHeight: 1.15, mt: 1 }}>
            多房并发投屏
            <br />
            会议管理系统
          </Typography>
          <Typography variant="body1" sx={{ mt: 2, opacity: 0.85, maxWidth: 420 }}>
            集中管理全部会议室的投屏、成员、审批与实时预警, 让每一场小会都稳稳开起来。
          </Typography>
          <Stack direction="row" flexWrap="wrap" sx={{ mt: 3, gap: 1 }}>
            {FEATURES.map((f) => (
              <Box
                key={f}
                sx={{
                  px: 1.5, py: 0.5, borderRadius: 999, fontSize: 13,
                  bgcolor: 'rgba(255,255,255,0.14)', border: '1px solid rgba(255,255,255,0.25)',
                }}
              >
                {f}
              </Box>
            ))}
          </Stack>
        </Box>

        <Card
          sx={{
            width: '100%',
            maxWidth: 420,
            borderRadius: 4,
            backdropFilter: 'blur(8px)',
            background: 'rgba(255, 255, 255, 0.96)',
            boxShadow: '0 24px 64px rgba(15, 12, 60, 0.45)',
          }}
        >
          <CardContent sx={{ p: { xs: 3, sm: 4 } }}>
            <Box sx={{ textAlign: 'center', mb: 3 }}>
              <Box
                sx={{
                  width: 64, height: 64, mx: 'auto', borderRadius: 3,
                  display: 'flex', alignItems: 'center', justifyContent: 'center',
                  background: 'linear-gradient(135deg, #4f46e5, #8b7ff8)',
                  boxShadow: '0 12px 28px rgba(79,70,229,0.35)',
                }}
              >
                <CastConnectedIcon sx={{ fontSize: 34, color: '#fff' }} />
              </Box>
              <Typography variant="h5" sx={{ mt: 2 }}>
                管理员登录
              </Typography>
              <Typography variant="body2" color="text.secondary">
                公司 PC 管理端 · 后台隐藏身份
              </Typography>
            </Box>
            {error && (
              <Alert severity="error" sx={{ mb: 2 }} role="alert">
                {error}
              </Alert>
            )}
            <form onSubmit={submit} noValidate>
              <TextField
                fullWidth
                label="账号"
                autoComplete="username"
                autoFocus
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
                type={showPassword ? 'text' : 'password'}
                label="密码"
                autoComplete="current-password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                sx={{ mb: 3 }}
                InputProps={{
                  startAdornment: (
                    <InputAdornment position="start">
                      <LockIcon color="action" />
                    </InputAdornment>
                  ),
                  endAdornment: (
                    <InputAdornment position="end">
                      <IconButton
                        aria-label={showPassword ? '隐藏密码' : '显示密码'}
                        onClick={() => setShowPassword((v) => !v)}
                        edge="end"
                        size="small"
                      >
                        {showPassword ? <VisibilityOff /> : <Visibility />}
                      </IconButton>
                    </InputAdornment>
                  ),
                }}
              />
              <Button
                fullWidth
                size="large"
                type="submit"
                variant="contained"
                disabled={loading || !username.trim() || !password}
                sx={{ py: 1.4, fontSize: 16 }}
              >
                {loading ? <CircularProgress size={24} color="inherit" /> : '登 录'}
              </Button>
            </form>
          </CardContent>
        </Card>
      </Stack>
    </Box>
  )
}
