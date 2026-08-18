import { useCallback, useEffect, useState } from 'react'
import {
  Alert, Box, Button, Card, CardContent, Chip, Dialog, DialogActions,
  DialogContent, DialogTitle, IconButton, MenuItem, Table, TableBody,
  TableCell, TableHead, TableRow, TextField, Tooltip, Typography,
} from '@mui/material'
import AddIcon from '@mui/icons-material/Add'
import EditIcon from '@mui/icons-material/Edit'
import DeleteIcon from '@mui/icons-material/Delete'
import { createUser, deleteUser, listUsers, updateUser } from '../api'

const roleLabels = {
  ADMIN: '管理员',
}

const emptyForm = {
  username: '',
  password: '',
  displayName: '',
  role: 'ADMIN',
}

export default function UsersPage() {
  const [users, setUsers] = useState([])
  const [dialogOpen, setDialogOpen] = useState(false)
  const [editing, setEditing] = useState(null)
  const [form, setForm] = useState(emptyForm)
  const [error, setError] = useState('')

  const refresh = useCallback(async () => {
    setUsers(await listUsers())
  }, [])

  useEffect(() => {
    refresh().catch((err) => setError(err.message))
  }, [refresh])

  const openCreate = () => {
    setEditing(null)
    setForm(emptyForm)
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
    setDialogOpen(true)
  }

  const submit = async () => {
    setError('')
    try {
      if (editing) {
        await updateUser(editing.id, {
          displayName: form.displayName || null,
          role: form.role,
          password: form.password || null,
        })
      } else {
        await createUser({
          username: form.username,
          password: form.password,
          displayName: form.displayName || null,
          role: form.role,
        })
      }
      setDialogOpen(false)
      await refresh()
    } catch (err) {
      setError(err.message)
    }
  }

  const remove = async (user) => {
    try {
      await deleteUser(user.id)
      await refresh()
    } catch (err) {
      setError(err.message)
    }
  }

  const currentUsername = localStorage.getItem('admin_username')

  return (
    <Box>
      <Box sx={{ display: 'flex', alignItems: 'center', mb: 3 }}>
        <Typography variant="h5" sx={{ flexGrow: 1 }}>用户管理</Typography>
        <Button variant="contained" startIcon={<AddIcon />} onClick={openCreate}>
          添加用户
        </Button>
      </Box>
      {error && <Alert severity="error" sx={{ mb: 2 }} onClose={() => setError('')}>{error}</Alert>}
      <Card>
        <CardContent>
          <Table>
            <TableHead>
              <TableRow>
                <TableCell>用户名</TableCell>
                <TableCell>显示名称</TableCell>
                <TableCell>角色</TableCell>
                <TableCell>创建时间</TableCell>
                <TableCell align="right">操作</TableCell>
              </TableRow>
            </TableHead>
            <TableBody>
              {users.map((user) => (
                <TableRow key={user.id} hover>
                  <TableCell>{user.username}</TableCell>
                  <TableCell>{user.displayName || '-'}</TableCell>
                  <TableCell>
                    <Chip size="small" label={roleLabels[user.role] || user.role} />
                  </TableCell>
                  <TableCell>{user.createdAt?.replace('T', ' ')}</TableCell>
                  <TableCell align="right">
                    <Tooltip title="编辑">
                      <IconButton onClick={() => openEdit(user)}><EditIcon /></IconButton>
                    </Tooltip>
                    <Tooltip title="删除">
                      <span>
                        <IconButton
                          color="error"
                          disabled={user.username === currentUsername}
                          onClick={() => remove(user)}
                        >
                          <DeleteIcon />
                        </IconButton>
                      </span>
                    </Tooltip>
                  </TableCell>
                </TableRow>
              ))}
              {users.length === 0 && (
                <TableRow>
                  <TableCell colSpan={5}>
                    <Typography color="text.secondary" align="center" sx={{ py: 3 }}>
                      暂无用户
                    </Typography>
                  </TableCell>
                </TableRow>
              )}
            </TableBody>
          </Table>
        </CardContent>
      </Card>

      <Dialog open={dialogOpen} onClose={() => setDialogOpen(false)} maxWidth="xs" fullWidth>
        <DialogTitle>{editing ? '编辑用户' : '添加用户'}</DialogTitle>
        <DialogContent sx={{ display: 'flex', flexDirection: 'column', gap: 2, pt: '12px !important' }}>
          <TextField
            label="用户名"
            value={form.username}
            disabled={!!editing}
            onChange={(e) => setForm({ ...form, username: e.target.value })}
          />
          <TextField
            label={editing ? '新密码(留空不修改)' : '密码'}
            type="password"
            value={form.password}
            onChange={(e) => setForm({ ...form, password: e.target.value })}
          />
          <TextField
            label="显示名称"
            value={form.displayName}
            onChange={(e) => setForm({ ...form, displayName: e.target.value })}
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
        <DialogActions>
          <Button onClick={() => setDialogOpen(false)}>取消</Button>
          <Button
            variant="contained"
            onClick={submit}
            disabled={!form.username || (!editing && !form.password)}
          >
            保存
          </Button>
        </DialogActions>
      </Dialog>
    </Box>
  )
}
