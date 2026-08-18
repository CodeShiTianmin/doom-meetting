import { Navigate, Route, Routes } from 'react-router-dom'
import JoinPage from './pages/JoinPage.jsx'
import RoomPage from './pages/RoomPage.jsx'

export default function App() {
  return (
    <Routes>
      <Route path="/join" element={<JoinPage />} />
      <Route path="/room" element={<RoomPage />} />
      <Route path="*" element={<Navigate to="/join" replace />} />
    </Routes>
  )
}
