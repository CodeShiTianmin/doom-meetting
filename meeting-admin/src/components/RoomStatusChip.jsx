import { Chip } from '@mui/material'

const statusMap = {
  WAITING: { label: '等待中', color: 'warning' },
  RUNNING: { label: '运行中', color: 'success' },
  CLOSED: { label: '已关闭', color: 'default' },
}

export default function RoomStatusChip({ status }) {
  const item = statusMap[status] || { label: status, color: 'default' }
  return <Chip size="small" label={item.label} color={item.color} />
}
