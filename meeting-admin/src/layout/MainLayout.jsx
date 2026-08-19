import { useEffect, useState } from 'react'
import { Outlet, useLocation, useNavigate } from 'react-router-dom'
import {
  AppBar, Badge, Box, Divider, Drawer, IconButton, List, ListItemButton,
  ListItemIcon, ListItemText, Popover, Toolbar, Tooltip, Typography,
} from '@mui/material'
import DashboardIcon from '@mui/icons-material/Dashboard'
import MeetingRoomIcon from '@mui/icons-material/MeetingRoom'
import ScheduleIcon from '@mui/icons-material/Schedule'
import PeopleIcon from '@mui/icons-material/People'
import FavoriteIcon from '@mui/icons-material/Favorite'
import LogoutIcon from '@mui/icons-material/Logout'
import CastConnectedIcon from '@mui/icons-material/CastConnected'
import NotificationsIcon from '@mui/icons-material/Notifications'
import { connectWs, subscribeAdminDashboard } from '../api/ws'

const drawerWidth = 232

const menus = [
  { path: '/dashboard', label: '仪表盘', icon: <DashboardIcon /> },
  { path: '/rooms', label: '房间管理', icon: <MeetingRoomIcon /> },
  { path: '/schedules', label: '投放计划', icon: <ScheduleIcon /> },
  { path: '/likes', label: '点赞记录', icon: <FavoriteIcon /> },
  { path: '/users', label: '用户管理', icon: <PeopleIcon /> },
]

function describeEvent(event) {
  const payload = event.payload || {}
  switch (event.type) {
    case 'UNDERSTAFFED_ALERT':
      return { title: `房间 ${payload.name || event.roomCode} 缺人预警`, detail: `在线 ${payload.onlineCount ?? '-'}/${payload.maxMembers ?? '-'} · 缺人已超时` }
    case 'MEMBER_JOINED':
      return { title: `${payload.nickname || '用户'} 加入房间 ${event.roomCode}`, detail: `当前在线 ${payload.onlineCount ?? '-'}` }
    case 'MEMBER_LEFT':
      return { title: `${payload.nickname || '用户'} 离开房间 ${event.roomCode}`, detail: `当前在线 ${payload.onlineCount ?? '-'}` }
    default:
      return null
  }
}

export default function MainLayout() {
  const navigate = useNavigate()
  const location = useLocation()
  const [notifications, setNotifications] = useState([])
  const [unread, setUnread] = useState(0)
  const [anchorEl, setAnchorEl] = useState(null)
  const displayName = localStorage.getItem('admin_name') || '管理员'

  useEffect(() => {
    connectWs()
    const unsubscribe = subscribeAdminDashboard((event) => {
      const message = describeEvent(event)
      if (!message) return
      setNotifications((prev) => [
        { ...message, type: event.type, time: (event.timestamp || '').replace('T', ' ').slice(0, 19), key: `${Date.now()}-${Math.random()}` },
        ...prev,
      ].slice(0, 50))
      setUnread((count) => count + 1)
    })
    return unsubscribe
  }, [])

  const openNotifications = (e) => {
    setAnchorEl(e.currentTarget)
    setUnread(0)
  }

  const logout = () => {
    localStorage.removeItem('admin_token')
    localStorage.removeItem('admin_name')
    navigate('/login')
  }

  return (
    <Box sx={{ display: 'flex', minHeight: '100vh' }}>
      <AppBar
        position="fixed"
        elevation={0}
        sx={{
          zIndex: (theme) => theme.zIndex.drawer + 1,
          background: 'linear-gradient(90deg, #1e1b4b 0%, #4f46e5 55%, #7c6ff7 100%)',
        }}
      >
        <Toolbar>
          <CastConnectedIcon sx={{ mr: 1.5 }} />
          <Typography variant="h6" sx={{ flexGrow: 1 }}>
            多房并发投屏会议 · 管理系统
          </Typography>
          <Tooltip title="消息通知">
            <IconButton color="inherit" onClick={openNotifications} sx={{ mr: 2 }}>
              <Badge badgeContent={unread} color="error">
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
            <Box sx={{ width: 340, maxHeight: 420, overflow: 'auto' }}>
              <Typography variant="subtitle2" sx={{ px: 2, pt: 1.5, pb: 0.5 }}>消息通知</Typography>
              <Divider />
              <List dense>
                {notifications.map((item) => (
                  <ListItemButton key={item.key} sx={{ alignItems: 'flex-start' }}>
                    <ListItemText
                      primary={item.title}
                      secondary={`${item.detail} · ${item.time}`}
                      primaryTypographyProps={{
                        variant: 'body2',
                        color: item.type === 'UNDERSTAFFED_ALERT' ? 'error' : 'text.primary',
                      }}
                      secondaryTypographyProps={{ variant: 'caption' }}
                    />
                  </ListItemButton>
                ))}
                {notifications.length === 0 && (
                  <Typography variant="body2" color="text.secondary" sx={{ p: 2 }}>暂无消息</Typography>
                )}
              </List>
            </Box>
          </Popover>
          <Typography sx={{ mr: 1 }}>{displayName}</Typography>
          <Tooltip title="退出登录">
            <IconButton color="inherit" onClick={logout}>
              <LogoutIcon />
            </IconButton>
          </Tooltip>
        </Toolbar>
      </AppBar>
      <Drawer
        variant="permanent"
        sx={{
          width: drawerWidth,
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
        <Toolbar />
        <List sx={{ px: 1.5, pt: 2 }}>
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
                <ListItemText primary={menu.label} />
              </ListItemButton>
            )
          })}
        </List>
        <Divider sx={{ mt: 'auto', borderColor: 'rgba(255, 255, 255, 0.12)' }} />
        <Typography variant="caption" sx={{ p: 2, color: 'rgba(255, 255, 255, 0.45)' }}>
          上传文件投放 · 会议结束自动清理
        </Typography>
      </Drawer>
      <Box component="main" sx={{ flexGrow: 1, p: 3 }}>
        <Toolbar />
        <Outlet />
      </Box>
    </Box>
  )
}
