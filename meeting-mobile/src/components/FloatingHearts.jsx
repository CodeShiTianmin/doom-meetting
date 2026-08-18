import { Box, keyframes } from '@mui/material'
import FavoriteIcon from '@mui/icons-material/Favorite'

const floatUp = keyframes`
  0% { transform: translateY(0) scale(0.6); opacity: 0.9; }
  70% { opacity: 0.8; }
  100% { transform: translateY(-220px) scale(1.25); opacity: 0; }
`

/**
 * 点赞飘心动画(房间内实时点赞反馈)
 */
export default function FloatingHearts({ hearts }) {
  return (
    <Box sx={{ position: 'absolute', right: 18, bottom: 120, pointerEvents: 'none', zIndex: 30 }}>
      {hearts.map((heart) => (
        <FavoriteIcon
          key={heart.id}
          sx={{
            position: 'absolute',
            bottom: 0,
            right: heart.offset,
            color: heart.color,
            fontSize: 26 + (heart.id % 10),
            animation: `${floatUp} 1.8s ease-out forwards`,
          }}
        />
      ))}
    </Box>
  )
}
