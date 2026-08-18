import client from './client'

// ---------- 认证 ----------
export const login = (username, password) =>
  client.post('/auth/login', { username, password })

// ---------- 房间 ----------
export const createRoom = (data) => client.post('/admin/rooms', data)
export const listRooms = (status) =>
  client.get('/admin/rooms', { params: status ? { status } : {} })
export const getRoom = (id) => client.get(`/admin/rooms/${id}`)
export const updateRoomSettings = (id, data) =>
  client.put(`/admin/rooms/${id}/settings`, data)
export const castContent = (id, contentId) =>
  client.post(`/admin/rooms/${id}/cast`, { contentId })
export const closeRoom = (id) => client.post(`/admin/rooms/${id}/close`)
export const regenerateInvite = (id) =>
  client.post(`/admin/rooms/${id}/invite/regenerate`)
export const getPublisherToken = (id) =>
  client.get(`/admin/rooms/${id}/publisher-token`)
export const listRoomMembers = (id) => client.get(`/admin/rooms/${id}/members`)
export const listRoomLikes = (id) => client.get(`/admin/rooms/${id}/likes`)
export const listRoomEvents = (id) => client.get(`/admin/rooms/${id}/events`)

// ---------- 内容 ----------
export const createContent = (data) => client.post('/admin/contents', data)
export const listContents = (includeDisabled) =>
  client.get('/admin/contents', { params: includeDisabled ? { includeDisabled: true } : {} })
export const updateContent = (id, data) => client.put(`/admin/contents/${id}`, data)
export const deleteContent = (id) => client.delete(`/admin/contents/${id}`)

// ---------- 投放计划 ----------
export const createSchedule = (data) => client.post('/admin/cast-schedules', data)
export const listSchedules = () => client.get('/admin/cast-schedules')
export const cancelSchedule = (id) => client.post(`/admin/cast-schedules/${id}/cancel`)

// ---------- 仪表盘 / 点赞 ----------
export const getDashboardSummary = () => client.get('/admin/dashboard/summary')
export const listAllLikes = () => client.get('/admin/likes')

// ---------- 用户管理 ----------
export const listUsers = () => client.get('/admin/users')
export const createUser = (data) => client.post('/admin/users', data)
export const updateUser = (id, data) => client.put(`/admin/users/${id}`, data)
export const deleteUser = (id) => client.delete(`/admin/users/${id}`)
