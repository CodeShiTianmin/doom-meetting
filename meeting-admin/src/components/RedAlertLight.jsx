import { Box, Tooltip } from '@mui/material'
import { keyframes } from '@emotion/react'

const blink = keyframes`
  0% { opacity: 1; box-shadow: 0 0 6px 2px rgba(229, 57, 53, 0.8); }
  50% { opacity: 0.35; box-shadow: 0 0 2px 0 rgba(229, 57, 53, 0.3); }
  100% { opacity: 1; box-shadow: 0 0 6px 2px rgba(229, 57, 53, 0.8); }
`

/**
 * 红灯预警指示灯: 房间缺人超过服务端配置的时长时闪烁红灯
 */
export default function RedAlertLight({ on, since, size = 14 }) {
  if (!on) {
    return (
      <Tooltip title="人员状态正常">
        <Box
          role="img"
          aria-label="人员状态正常"
          sx={{ width: size, height: size, borderRadius: '50%', background: '#c8cdda', flexShrink: 0 }}
        />
      </Tooltip>
    )
  }
  const sinceText = since ? ` (自 ${String(since).replace('T', ' ').slice(0, 16)})` : ''
  return (
    <Tooltip title={`红灯预警: 房间缺人已超时${sinceText}`}>
      <Box
        role="img"
        aria-label="红灯预警"
        sx={{
          width: size, height: size, borderRadius: '50%', background: '#e53935', flexShrink: 0,
          animation: `${blink} 1s infinite`,
        }}
      />
    </Tooltip>
  )
}
