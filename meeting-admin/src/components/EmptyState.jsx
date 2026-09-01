import { Box, Typography } from '@mui/material'
import InboxIcon from '@mui/icons-material/Inbox'

/**
 * 列表/表格空状态占位
 */
export default function EmptyState({ icon, title = '暂无数据', description, action, compact = false, sx }) {
  const Icon = icon || InboxIcon
  return (
    <Box
      sx={{
        py: compact ? 3 : 6,
        px: 2,
        textAlign: 'center',
        color: 'text.secondary',
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        gap: 1,
        ...sx,
      }}
    >
      <Box
        sx={{
          width: compact ? 44 : 64,
          height: compact ? 44 : 64,
          borderRadius: '50%',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          bgcolor: 'rgba(79, 70, 229, 0.08)',
          color: 'primary.main',
        }}
      >
        <Icon sx={{ fontSize: compact ? 22 : 30 }} />
      </Box>
      <Typography variant={compact ? 'body2' : 'subtitle1'} sx={{ fontWeight: 600, color: 'text.primary' }}>
        {title}
      </Typography>
      {description && (
        <Typography variant="body2" color="text.secondary" sx={{ maxWidth: 360 }}>
          {description}
        </Typography>
      )}
      {action && <Box sx={{ mt: 1 }}>{action}</Box>}
    </Box>
  )
}
