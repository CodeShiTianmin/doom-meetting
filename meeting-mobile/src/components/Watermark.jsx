import { useEffect, useState } from 'react'
import { Box } from '@mui/material'

/**
 * 全屏水印(客户昵称 + 时间), 威慑翻拍/录屏泄露
 */
export default function Watermark({ text }) {
  const [now, setNow] = useState(() => new Date())

  useEffect(() => {
    const timer = setInterval(() => setNow(new Date()), 30000)
    return () => clearInterval(timer)
  }, [])

  const stamp = `${text} ${now.toLocaleString('zh-CN', { hour12: false })}`
  const cells = Array.from({ length: 12 })

  return (
    <Box
      sx={{
        position: 'fixed', inset: 0, zIndex: 1200, pointerEvents: 'none',
        display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)',
        gridTemplateRows: 'repeat(4, 1fr)', overflow: 'hidden',
      }}
    >
      {cells.map((_, i) => (
        <Box
          key={i}
          sx={{
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            transform: 'rotate(-24deg)', color: 'rgba(255,255,255,0.08)',
            fontSize: 13, whiteSpace: 'nowrap', userSelect: 'none',
          }}
        >
          {stamp}
        </Box>
      ))}
    </Box>
  )
}
