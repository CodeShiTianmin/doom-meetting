import { Box, Tooltip } from '@mui/material'
import { keyframes } from '@emotion/react'

const blink = keyframes`
  0% { opacity: 1; box-shadow: 0 0 6px 2px rgba(229, 57, 53, 0.8); }
  50% { opacity: 0.35; box-shadow: 0 0 2px 0 rgba(229, 57, 53, 0.3); }
  100% { opacity: 1; box-shadow: 0 0 6px 2px rgba(229, 57, 53, 0.8); }
`

/**
 * 红灯预警指示灯: 房间创建后缺人超过 3 分钟时闪烁红灯
 */
export default function RedAlertLight({ on }) {
  if (!on) {
    return (
      <Tooltip title="人员状态正常">
        <Box sx={{ width: 14, height: 14, borderRadius: '50%', background: '#c8cdda' }} />
      </Tooltip>
    )
  }
  return (
    <Tooltip title="红灯预警: 缺人超过3分钟">
      <Box
        sx={{
          width: 14, height: 14, borderRadius: '50%', background: '#e53935',
          animation: `${blink} 1s infinite`,
        }}
      />
    </Tooltip>
  )
}
