import { Navigate, Route, Routes } from 'react-router-dom'
import LoginPage from './pages/LoginPage.jsx'
import MainLayout from './layout/MainLayout.jsx'
import DashboardPage from './pages/DashboardPage.jsx'
import RoomsPage from './pages/RoomsPage.jsx'
import RoomDetailPage from './pages/RoomDetailPage.jsx'
import ContentsPage from './pages/ContentsPage.jsx'
import SchedulesPage from './pages/SchedulesPage.jsx'
import LikesPage from './pages/LikesPage.jsx'

function RequireAuth({ children }) {
  const token = localStorage.getItem('admin_token')
  if (!token) return <Navigate to="/login" replace />
  return children
}

export default function App() {
  return (
    <Routes>
      <Route path="/login" element={<LoginPage />} />
      <Route
        path="/"
        element={
          <RequireAuth>
            <MainLayout />
          </RequireAuth>
        }
      >
        <Route index element={<Navigate to="/dashboard" replace />} />
        <Route path="dashboard" element={<DashboardPage />} />
        <Route path="rooms" element={<RoomsPage />} />
        <Route path="rooms/:id" element={<RoomDetailPage />} />
        <Route path="contents" element={<ContentsPage />} />
        <Route path="schedules" element={<SchedulesPage />} />
        <Route path="likes" element={<LikesPage />} />
      </Route>
      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  )
}
