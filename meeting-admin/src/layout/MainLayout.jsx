import { useEffect, useState } from 'react'
import { Outlet, useLocation, useNavigate } from 'react-router-dom'
import {
  AppBar, Avatar, Badge, Box, Divider, Drawer, IconButton, List, ListItemButton,
  ListItemIcon, ListItemText, Toolbar, Tooltip, Typography,
} from '@mui/material'
import DashboardIcon from '@mui/icons-material/Dashboard'
import MeetingRoomIcon from '@mui/icons-material/MeetingRoom'
import MovieIcon from '@mui/icons-material/Movie'
import ScheduleIcon from '@mui/icons-material/Schedule'
import FavoriteIcon from '@mui/icons-material/Favorite'
import LogoutIcon from '@mui/icons-material/Logout'
import CastConnectedIcon from '@mui/icons-material/CastConnected'
import WarningAmberIcon from '@mui/icons-material/WarningAmber'
import { connectWs, subscribeAdminDashboard } from '../api/ws'

const drawerWidth = 232

const menus = [
  { path: '/dashboard', label: '仪表盘', icon: <DashboardIcon /> },
  { path: '/rooms', label: '房间管理', icon: <MeetingRoomIcon /> },
  { path: '/contents', label: '投放内容', icon: <MovieIcon /> },
  { path: '/schedules', label: '投放计划', icon: <ScheduleIcon /> },
  { path: '/likes', label: '点赞记录', icon: <FavoriteIcon /> },
]

export default function MainLayout() {
  const navigate = useNavigate()
  const location = useLocation()
  const [alertCount, setAlertCount] = useState(0)
  const displayName = localStorage.getItem('admin_name') || '管理员'

  useEffect(() => {
    connectWs()
    const unsubscribe = subscribeAdminDashboard((event) => {
      if (event.type === 'UNDERSTAFFED_ALERT') {
        setAlertCount((count) => count + 1)
      }
      if (event.type === 'ROOM_RUNNING' || event.type === 'ROOM_CLOSED') {
        setAlertCount(0)
      }
    })
    return unsubscribe
  }, [])

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
          <Tooltip title="缺人红灯预警数">
            <Badge badgeContent={alertCount} color="error" sx={{ mr: 3 }}>
              <WarningAmberIcon />
            </Badge>
          </Tooltip>
          <Avatar sx={{ width: 32, height: 32, bgcolor: '#00bfa5', mr: 1 }}>
            {displayName.slice(0, 1)}
          </Avatar>
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
          媒体零留存 · 仅记录元数据
        </Typography>
      </Drawer>
      <Box component="main" sx={{ flexGrow: 1, p: 3 }}>
        <Toolbar />
        <Outlet />
      </Box>
    </Box>
  )
}
