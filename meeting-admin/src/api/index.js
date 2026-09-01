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
export const startCast = (id, type, label, replace = false) =>
  client.post(`/admin/rooms/${id}/cast/start`, { type, label, replace })
export const stopCast = (id) => client.post(`/admin/rooms/${id}/cast/stop`)
export const closeRoom = (id) => client.post(`/admin/rooms/${id}/close`)
export const resetRoom = (id) => client.post(`/admin/rooms/${id}/reset`)
export const deleteRoom = (id) => client.delete(`/admin/rooms/${id}`)
export const regenerateInvite = (id) =>
  client.post(`/admin/rooms/${id}/invite/regenerate`)
export const getPublisherToken = (id) =>
  client.get(`/admin/rooms/${id}/publisher-token`)
export const listRoomMembers = (id) => client.get(`/admin/rooms/${id}/members`)
export const listRoomLikes = (id) => client.get(`/admin/rooms/${id}/likes`)
export const listRoomEvents = (id) => client.get(`/admin/rooms/${id}/events`)

// ---------- 成员管理 ----------
export const kickMember = (id, identity) =>
  client.post(`/admin/rooms/${id}/members/${identity}/kick`)
export const muteMember = (id, identity, muted) =>
  client.post(`/admin/rooms/${id}/members/${identity}/mute`, null, { params: { muted } })
export const muteAllMembers = (id, muted) =>
  client.post(`/admin/rooms/${id}/members/mute-all`, null, { params: { muted } })
export const setMemberCamera = (id, identity, disabled) =>
  client.post(`/admin/rooms/${id}/members/${identity}/camera`, null, { params: { disabled } })
export const approveMember = (id, identity, approved) =>
  client.post(`/admin/rooms/${id}/members/${identity}/approve`, null, { params: { approved } })
export const getAttendance = (id) => client.get(`/admin/rooms/${id}/attendance`)

// ---------- 仪表盘 / 点赞 ----------
export const getDashboardSummary = () => client.get('/admin/dashboard/summary')
export const getDashboardTrends = (days = 7) =>
  client.get('/admin/dashboard/trends', { params: { days } })
export const listAllLikes = () => client.get('/admin/likes')

// ---------- 用户管理 ----------
export const listUsers = () => client.get('/admin/users')
export const createUser = (data) => client.post('/admin/users', data)
export const updateUser = (id, data) => client.put(`/admin/users/${id}`, data)
export const deleteUser = (id) => client.delete(`/admin/users/${id}`)
