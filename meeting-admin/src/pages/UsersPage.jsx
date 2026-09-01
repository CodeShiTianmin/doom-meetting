import { useCallback, useEffect, useMemo, useState } from 'react'
import {
  Alert, Avatar, Box, Button, Card, Chip, CircularProgress, Dialog, DialogActions,
  DialogContent, DialogTitle, IconButton, InputAdornment, MenuItem, Stack, Table, TableBody,
  TableCell, TableContainer, TableHead, TableRow, TextField, Tooltip, Typography,
} from '@mui/material'
import AddIcon from '@mui/icons-material/Add'
import EditIcon from '@mui/icons-material/Edit'
import DeleteIcon from '@mui/icons-material/Delete'
import RefreshIcon from '@mui/icons-material/Refresh'
import PeopleIcon from '@mui/icons-material/People'
import Visibility from '@mui/icons-material/Visibility'
import VisibilityOff from '@mui/icons-material/VisibilityOff'
import { createUser, deleteUser, listUsers, updateUser } from '../api'
import PageHeader from '../components/PageHeader.jsx'
import EmptyState from '../components/EmptyState.jsx'
import ConfirmDialog from '../components/ConfirmDialog.jsx'

const roleLabels = {
  ADMIN: '管理员',
}

const emptyForm = {
  username: '',
  password: '',
  displayName: '',
  role: 'ADMIN',
}

const PASSWORD_MIN = 6
const PASSWORD_MAX = 64

function validate(form, editing) {
  const errors = {}
  const username = form.username.trim()
  if (!editing) {
    if (!username) errors.username = '请输入用户名'
    else if (username.length > 64) errors.username = '用户名最多 64 个字符'
  }
  if (!editing && !form.password) errors.password = '请输入密码'
  if (form.password && (form.password.length < PASSWORD_MIN || form.password.length > PASSWORD_MAX)) {
    errors.password = `密码长度需为 ${PASSWORD_MIN}-${PASSWORD_MAX} 位`
  }
  if (form.displayName.length > 64) errors.displayName = '显示名称最多 64 个字符'
  return errors
}

export default function UsersPage() {
  const [users, setUsers] = useState([])
  const [loading, setLoading] = useState(true)
  const [dialogOpen, setDialogOpen] = useState(false)
  const [editing, setEditing] = useState(null)
  const [form, setForm] = useState(emptyForm)
  const [showPassword, setShowPassword] = useState(false)
  const [submitting, setSubmitting] = useState(false)
  const [formError, setFormError] = useState('')
  const [error, setError] = useState('')
  const [pendingDelete, setPendingDelete] = useState(null)

  const refresh = useCallback(async () => {
    setLoading(true)
    try {
      const list = await listUsers()
      setUsers(Array.isArray(list) ? list : [])
      setError('')
    } catch (err) {
      setError(err.message || '加载用户列表失败')
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    refresh()
  }, [refresh])

  const formErrors = useMemo(() => validate(form, editing), [form, editing])
  const formValid = Object.keys(formErrors).length === 0

  const openCreate = () => {
    setEditing(null)
    setForm(emptyForm)
    setFormError('')
    setShowPassword(false)
    setDialogOpen(true)
  }

  const openEdit = (user) => {
    setEditing(user)
    setForm({
      username: user.username,
      password: '',
      displayName: user.displayName || '',
      role: user.role,
    })
    setFormError('')
    setShowPassword(false)
    setDialogOpen(true)
  }

  const closeDialog = () => {
    if (submitting) return
    setDialogOpen(false)
  }

  const submit = async (e) => {
    e?.preventDefault?.()
    if (submitting || !formValid) return
    setFormError('')
    setSubmitting(true)
    try {
      if (editing) {
        await updateUser(editing.id, {
          displayName: form.displayName.trim() || null,
          role: form.role,
          password: form.password || null,
        })
      } else {
        await createUser({
          username: form.username.trim(),
          password: form.password,
          displayName: form.displayName.trim() || null,
          role: form.role,
        })
      }
      setDialogOpen(false)
      await refresh()
    } catch (err) {
      setFormError(err.message || '保存失败, 请稍后重试')
    } finally {
      setSubmitting(false)
    }
  }

  const remove = async (user) => {
    setError('')
    try {
      await deleteUser(user.id)
      await refresh()
    } catch (err) {
      setError(err.message || '删除失败')
      throw err
    }
  }

  const currentUsername = localStorage.getItem('admin_username')

  return (
    <Box>
      <PageHeader
        title="用户管理"
        subtitle={`管理后台登录账号 · 共 ${users.length} 个`}
        actions={(
          <>
            <Tooltip title="刷新">
              <IconButton onClick={refresh} disabled={loading} aria-label="刷新">
                <RefreshIcon />
              </IconButton>
            </Tooltip>
            <Button variant="contained" startIcon={<AddIcon />} onClick={openCreate}>
              添加用户
            </Button>
          </>
        )}
      />
      {error && <Alert severity="error" sx={{ mb: 2 }} onClose={() => setError('')}>{error}</Alert>}

      <Card sx={{ overflow: 'hidden' }}>
        {loading ? (
          <Box sx={{ py: 8, display: 'flex', justifyContent: 'center' }}>
            <CircularProgress />
          </Box>
        ) : users.length === 0 ? (
          <EmptyState
            icon={PeopleIcon}
            title="暂无用户"
            description="添加后台登录账号以便多人协同管理"
            action={<Button variant="outlined" startIcon={<AddIcon />} onClick={openCreate}>添加用户</Button>}
          />
        ) : (
          <TableContainer>
            <Table sx={{ minWidth: 640 }}>
              <TableHead>
                <TableRow>
                  <TableCell>用户</TableCell>
                  <TableCell>显示名称</TableCell>
                  <TableCell>角色</TableCell>
                  <TableCell>创建时间</TableCell>
                  <TableCell align="right">操作</TableCell>
                </TableRow>
              </TableHead>
              <TableBody>
                {users.map((user) => {
                  const isSelf = user.username === currentUsername
                  return (
                    <TableRow key={user.id} hover>
                      <TableCell>
                        <Stack direction="row" alignItems="center" spacing={1.5}>
                          <Avatar sx={{ width: 32, height: 32, fontSize: 14, bgcolor: isSelf ? 'primary.main' : 'rgba(79, 70, 229, 0.15)', color: isSelf ? '#fff' : 'primary.main' }}>
                            {(user.displayName || user.username || '?').slice(0, 1).toUpperCase()}
                          </Avatar>
                          <Box>
                            <Typography variant="body2" sx={{ fontWeight: 600 }}>{user.username}</Typography>
                            {isSelf && <Typography variant="caption" color="primary">当前登录</Typography>}
                          </Box>
                        </Stack>
                      </TableCell>
                      <TableCell>{user.displayName || <Typography variant="body2" color="text.disabled">-</Typography>}</TableCell>
                      <TableCell>
                        <Chip size="small" color="primary" variant="outlined" label={roleLabels[user.role] || user.role} />
                      </TableCell>
                      <TableCell sx={{ whiteSpace: 'nowrap', color: 'text.secondary' }}>
                        {user.createdAt?.replace('T', ' ').slice(0, 19)}
                      </TableCell>
                      <TableCell align="right" sx={{ whiteSpace: 'nowrap' }}>
                        <Tooltip title="编辑">
                          <IconButton size="small" onClick={() => openEdit(user)} aria-label={`编辑 ${user.username}`}>
                            <EditIcon fontSize="small" />
                          </IconButton>
                        </Tooltip>
                        <Tooltip title={isSelf ? '不能删除当前登录账号' : '删除'}>
                          <span>
                            <IconButton
                              size="small"
                              color="error"
                              disabled={isSelf}
                              onClick={() => setPendingDelete(user)}
                              aria-label={`删除 ${user.username}`}
                            >
                              <DeleteIcon fontSize="small" />
                            </IconButton>
                          </span>
                        </Tooltip>
                      </TableCell>
                    </TableRow>
                  )
                })}
              </TableBody>
            </Table>
          </TableContainer>
        )}
      </Card>

      <Dialog open={dialogOpen} onClose={closeDialog} maxWidth="xs" fullWidth>
        <Box component="form" onSubmit={submit} noValidate>
          <DialogTitle>{editing ? '编辑用户' : '添加用户'}</DialogTitle>
          <DialogContent sx={{ display: 'flex', flexDirection: 'column', gap: 2, pt: '12px !important' }}>
            {formError && <Alert severity="error">{formError}</Alert>}
            <TextField
              label="用户名"
              value={form.username}
              disabled={!!editing}
              autoFocus={!editing}
              autoComplete="off"
              inputProps={{ maxLength: 64 }}
              onChange={(e) => setForm({ ...form, username: e.target.value })}
              error={Boolean(form.username && formErrors.username)}
              helperText={form.username ? formErrors.username : (editing ? '' : '用于登录, 创建后不可修改')}
            />
            <TextField
              label={editing ? '新密码(留空不修改)' : '密码'}
              type={showPassword ? 'text' : 'password'}
              value={form.password}
              autoFocus={!!editing}
              autoComplete="new-password"
              inputProps={{ maxLength: PASSWORD_MAX }}
              onChange={(e) => setForm({ ...form, password: e.target.value })}
              error={Boolean(form.password && formErrors.password)}
              helperText={form.password ? formErrors.password : `${PASSWORD_MIN}-${PASSWORD_MAX} 位`}
              InputProps={{
                endAdornment: (
                  <InputAdornment position="end">
                    <IconButton
                      aria-label={showPassword ? '隐藏密码' : '显示密码'}
                      onClick={() => setShowPassword((v) => !v)}
                      edge="end"
                      size="small"
                    >
                      {showPassword ? <VisibilityOff fontSize="small" /> : <Visibility fontSize="small" />}
                    </IconButton>
                  </InputAdornment>
                ),
              }}
            />
            <TextField
              label="显示名称"
              value={form.displayName}
              inputProps={{ maxLength: 64 }}
              onChange={(e) => setForm({ ...form, displayName: e.target.value })}
              error={Boolean(formErrors.displayName)}
              helperText={formErrors.displayName || '可选, 用于界面展示'}
            />
            <TextField
              select
              label="角色"
              value={form.role}
              onChange={(e) => setForm({ ...form, role: e.target.value })}
            >
              {Object.entries(roleLabels).map(([value, label]) => (
                <MenuItem key={value} value={value}>{label}</MenuItem>
              ))}
            </TextField>
          </DialogContent>
          <DialogActions sx={{ px: 3, pb: 2 }}>
            <Button onClick={closeDialog} disabled={submitting}>取消</Button>
            <Button
              type="submit"
              variant="contained"
              disabled={!formValid || submitting}
              startIcon={submitting ? <CircularProgress size={16} color="inherit" /> : null}
            >
              保存
            </Button>
          </DialogActions>
        </Box>
      </Dialog>

      <ConfirmDialog
        open={Boolean(pendingDelete)}
        title="删除用户"
        content={pendingDelete ? `确定删除用户“${pendingDelete.displayName || pendingDelete.username}”? 删除后该账号将无法登录管理后台。` : ''}
        confirmText="删除"
        onClose={() => setPendingDelete(null)}
        onConfirm={() => remove(pendingDelete)}
      />
    </Box>
  )
}
