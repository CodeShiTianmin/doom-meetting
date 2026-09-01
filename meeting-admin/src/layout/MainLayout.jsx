import { useEffect, useState } from 'react'
import { Outlet, useLocation, useNavigate } from 'react-router-dom'
import {
  AppBar, Avatar, Badge, Box, Chip, Divider, Drawer, IconButton, List, ListItemButton,
  ListItemIcon, ListItemText, Popover, Toolbar, Tooltip, Typography, useMediaQuery,
} from '@mui/material'
import { useTheme } from '@mui/material/styles'
import DashboardIcon from '@mui/icons-material/Dashboard'
import MeetingRoomIcon from '@mui/icons-material/MeetingRoom'
import PeopleIcon from '@mui/icons-material/People'
import FavoriteIcon from '@mui/icons-material/Favorite'
import LogoutIcon from '@mui/icons-material/Logout'
import MenuIcon from '@mui/icons-material/Menu'
import CastConnectedIcon from '@mui/icons-material/CastConnected'
import NotificationsIcon from '@mui/icons-material/Notifications'
import DeleteSweepIcon from '@mui/icons-material/DeleteSweep'
import { connectWs, disconnectWs, onWsStatusChange, subscribeAdminDashboard } from '../api/ws'

const drawerWidth = 232

const menus = [
  { path: '/dashboard', label: '仪表盘', icon: <DashboardIcon /> },
  { path: '/rooms', label: '房间管理', icon: <MeetingRoomIcon /> },
  { path: '/likes', label: '点赞记录', icon: <FavoriteIcon /> },
  { path: '/users', label: '用户管理', icon: <PeopleIcon /> },
]

const WS_STATUS = {
  connected: { label: '实时连接', color: 'success' },
  connecting: { label: '连接中…', color: 'warning' },
  disconnected: { label: '已断开', color: 'error' },
}

function describeEvent(event) {
  const payload = event.payload || {}
  switch (event.type) {
    case 'UNDERSTAFFED_ALERT':
      return { title: `房间 ${payload.name || event.roomCode} 缺人预警`, detail: `在线 ${payload.onlineCount ?? '-'}/${payload.maxMembers ?? '-'} · 缺人已超时` }
    case 'MEMBER_JOINED':
      return { title: `${payload.nickname || '用户'} 加入房间 ${event.roomCode}`, detail: `当前在线 ${payload.onlineCount ?? '-'}` }
    case 'MEMBER_LEFT':
      return { title: `${payload.nickname || '用户'} 离开房间 ${event.roomCode}`, detail: `当前在线 ${payload.onlineCount ?? '-'}` }
    case 'JOIN_REQUEST':
      return { title: `${payload.nickname || '用户'} 申请加入房间 ${event.roomCode}`, detail: `座位 ${payload.seatNo || '-'} · 等待审批` }
    case 'RECORDING_DETECTED':
      return { title: `房间 ${event.roomCode} 检测到录屏`, detail: `${payload.nickname || payload.identity || '成员'} 触发录屏检测` }
    default:
      return null
  }
}

function formatTime(timestamp) {
  if (!timestamp) return new Date().toLocaleTimeString('zh-CN', { hour12: false })
  const date = new Date(timestamp)
  if (Number.isNaN(date.getTime())) return String(timestamp).replace('T', ' ').slice(0, 19)
  return date.toLocaleString('zh-CN', { hour12: false })
}

export default function MainLayout() {
  const navigate = useNavigate()
  const location = useLocation()
  const theme = useTheme()
  const isMobile = useMediaQuery(theme.breakpoints.down('md'))
  const [mobileOpen, setMobileOpen] = useState(false)
  const [notifications, setNotifications] = useState([])
  const [unread, setUnread] = useState(0)
  const [anchorEl, setAnchorEl] = useState(null)
  const [wsStatus, setWsStatus] = useState('disconnected')
  const displayName = localStorage.getItem('admin_name') || '管理员'

  useEffect(() => {
    connectWs()
    const unsubscribeStatus = onWsStatusChange(setWsStatus)
    const unsubscribe = subscribeAdminDashboard((event) => {
      const message = describeEvent(event)
      if (!message) return
      setNotifications((prev) => [
        { ...message, type: event.type, time: formatTime(event.timestamp), key: `${Date.now()}-${Math.random()}` },
        ...prev,
      ].slice(0, 50))
      setUnread((count) => count + 1)
    })
    return () => {
      unsubscribe()
      unsubscribeStatus()
    }
  }, [])

  useEffect(() => {
    setMobileOpen(false)
  }, [location.pathname])

  const openNotifications = (e) => {
    setAnchorEl(e.currentTarget)
    setUnread(0)
  }

  const logout = () => {
    disconnectWs()
    localStorage.removeItem('admin_token')
    localStorage.removeItem('admin_name')
    localStorage.removeItem('admin_username')
    navigate('/login', { replace: true })
  }

  const wsChip = WS_STATUS[wsStatus] || WS_STATUS.disconnected

  const drawerContent = (
    <>
      <Toolbar sx={{ px: 2.5 }}>
        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1.25 }}>
          <Box
            sx={{
              width: 34, height: 34, borderRadius: 2, display: 'flex', alignItems: 'center',
              justifyContent: 'center', background: 'linear-gradient(135deg, #6d5ef5, #4f46e5)',
              boxShadow: '0 6px 16px rgba(79,70,229,0.45)',
            }}
          >
            <CastConnectedIcon sx={{ fontSize: 20, color: '#fff' }} />
          </Box>
          <Box>
            <Typography variant="subtitle2" sx={{ color: '#fff', lineHeight: 1.2 }}>投屏会议</Typography>
            <Typography variant="caption" sx={{ color: 'rgba(255,255,255,0.5)' }}>管理系统</Typography>
          </Box>
        </Box>
      </Toolbar>
      <List sx={{ px: 1.5, pt: 1 }}>
        {menus.map((menu) => {
          const selected = location.pathname.startsWith(menu.path)
          return (
            <ListItemButton
              key={menu.path}
              selected={selected}
              onClick={() => navigate(menu.path)}
              sx={{
                borderRadius: 2,
                mb: 0.5,
                color: 'rgba(255, 255, 255, 0.72)',
                '& .MuiListItemIcon-root': { color: 'rgba(255, 255, 255, 0.55)' },
                '&:hover': { background: 'rgba(255, 255, 255, 0.08)' },
                '&.Mui-selected': {
                  background: 'linear-gradient(135deg, rgba(109, 94, 245, 0.95), rgba(79, 70, 229, 0.9))',
                  color: '#ffffff',
                  boxShadow: '0 4px 14px rgba(79, 70, 229, 0.45)',
                  '& .MuiListItemIcon-root': { color: '#ffffff' },
                  '&:hover': { background: 'linear-gradient(135deg, rgba(109, 94, 245, 1), rgba(79, 70, 229, 1))' },
                },
              }}
            >
              <ListItemIcon sx={{ minWidth: 40 }}>{menu.icon}</ListItemIcon>
              <ListItemText primary={menu.label} primaryTypographyProps={{ fontWeight: selected ? 600 : 500 }} />
            </ListItemButton>
          )
        })}
      </List>
      <Divider sx={{ mt: 'auto', borderColor: 'rgba(255, 255, 255, 0.12)' }} />
      <Box sx={{ p: 2 }}>
        <Chip
          size="small"
          label={wsChip.label}
          color={wsChip.color}
          variant="outlined"
          sx={{ mb: 1, borderColor: 'currentColor', '& .MuiChip-label': { fontWeight: 600 } }}
        />
        <Typography variant="caption" sx={{ display: 'block', color: 'rgba(255, 255, 255, 0.45)' }}>
          上传文件投放 · 会议结束自动清理
        </Typography>
      </Box>
    </>
  )

  return (
    <Box sx={{ display: 'flex', minHeight: '100vh' }}>
      <AppBar
        position="fixed"
        elevation={0}
        sx={{
          zIndex: (t) => t.zIndex.drawer + 1,
          background: 'linear-gradient(90deg, #1e1b4b 0%, #4f46e5 55%, #7c6ff7 100%)',
        }}
      >
        <Toolbar>
          {isMobile && (
            <IconButton color="inherit" edge="start" onClick={() => setMobileOpen(true)} sx={{ mr: 1 }} aria-label="打开菜单">
              <MenuIcon />
            </IconButton>
          )}
          {!isMobile && <CastConnectedIcon sx={{ mr: 1.5 }} />}
          <Typography variant="h6" noWrap sx={{ flexGrow: 1, fontSize: { xs: 16, sm: 20 } }}>
            {isMobile ? '投屏会议管理' : '多房并发投屏会议 · 管理系统'}
          </Typography>
          <Tooltip title="消息通知">
            <IconButton color="inherit" onClick={openNotifications} sx={{ mr: { xs: 0.5, sm: 2 } }} aria-label="消息通知">
              <Badge badgeContent={unread} color="error" max={99}>
                <NotificationsIcon />
              </Badge>
            </IconButton>
          </Tooltip>
          <Popover
            open={Boolean(anchorEl)}
            anchorEl={anchorEl}
            onClose={() => setAnchorEl(null)}
            anchorOrigin={{ vertical: 'bottom', horizontal: 'right' }}
            transformOrigin={{ vertical: 'top', horizontal: 'right' }}
          >
            <Box sx={{ width: { xs: 300, sm: 360 }, maxHeight: 440, display: 'flex', flexDirection: 'column' }}>
              <Box sx={{ px: 2, py: 1.25, display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
                <Typography variant="subtitle2">消息通知</Typography>
                {notifications.length > 0 && (
                  <Tooltip title="清空">
                    <IconButton size="small" onClick={() => setNotifications([])} aria-label="清空通知">
                      <DeleteSweepIcon fontSize="small" />
                    </IconButton>
                  </Tooltip>
                )}
              </Box>
              <Divider />
              <List dense sx={{ overflow: 'auto', flex: 1 }}>
                {notifications.map((item) => (
                  <ListItemButton key={item.key} sx={{ alignItems: 'flex-start' }}>
                    <ListItemText
                      primary={item.title}
                      secondary={`${item.detail} · ${item.time}`}
                      primaryTypographyProps={{
                        variant: 'body2',
                        fontWeight: 600,
                        color: item.type === 'UNDERSTAFFED_ALERT' || item.type === 'RECORDING_DETECTED' ? 'error' : 'text.primary',
                      }}
                      secondaryTypographyProps={{ variant: 'caption' }}
                    />
                  </ListItemButton>
                ))}
                {notifications.length === 0 && (
                  <Box sx={{ p: 3, textAlign: 'center' }}>
                    <NotificationsIcon sx={{ color: 'text.disabled', fontSize: 36 }} />
                    <Typography variant="body2" color="text.secondary">暂无消息</Typography>
                  </Box>
                )}
              </List>
            </Box>
          </Popover>
          <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, mr: 0.5 }}>
            <Avatar sx={{ width: 30, height: 30, bgcolor: 'rgba(255,255,255,0.22)', fontSize: 14 }}>
              {displayName.slice(0, 1).toUpperCase()}
            </Avatar>
            <Typography sx={{ display: { xs: 'none', sm: 'block' } }}>{displayName}</Typography>
          </Box>
          <Tooltip title="退出登录">
            <IconButton color="inherit" onClick={logout} aria-label="退出登录">
              <LogoutIcon />
            </IconButton>
          </Tooltip>
        </Toolbar>
      </AppBar>
      <Drawer
        variant={isMobile ? 'temporary' : 'permanent'}
        open={isMobile ? mobileOpen : true}
        onClose={() => setMobileOpen(false)}
        ModalProps={{ keepMounted: true }}
        sx={{
          width: isMobile ? 0 : drawerWidth,
          flexShrink: 0,
          '& .MuiDrawer-paper': {
            width: drawerWidth,
            boxSizing: 'border-box',
            borderRight: 'none',
            background: 'linear-gradient(180deg, #1e1b4b 0%, #262457 100%)',
            color: 'rgba(255, 255, 255, 0.78)',
          },
        }}
      >
        {drawerContent}
      </Drawer>
      <Box component="main" sx={{ flexGrow: 1, minWidth: 0, p: { xs: 2, sm: 3 } }}>
        <Toolbar />
        <Outlet />
      </Box>
    </Box>
  )
}
