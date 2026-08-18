import { useCallback, useEffect, useState } from 'react'
import {
  Alert, Box, Button, Card, CardContent, Chip, Dialog, DialogActions,
  DialogContent, DialogTitle, IconButton, MenuItem, Switch, Table, TableBody,
  TableCell, TableHead, TableRow, TextField, Tooltip, Typography,
} from '@mui/material'
import AddIcon from '@mui/icons-material/Add'
import EditIcon from '@mui/icons-material/Edit'
import DeleteIcon from '@mui/icons-material/Delete'
import { createContent, deleteContent, listContents, updateContent } from '../api'

const typeLabels = {
  LOCAL_FILE: '本地文件',
  SCREEN: '整屏共享',
  WINDOW: '窗口共享',
}

const emptyForm = {
  name: '',
  description: '',
  type: 'LOCAL_FILE',
  localPath: '',
  durationSeconds: '',
}

export default function ContentsPage() {
  const [contents, setContents] = useState([])
  const [dialogOpen, setDialogOpen] = useState(false)
  const [editing, setEditing] = useState(null)
  const [form, setForm] = useState(emptyForm)
  const [error, setError] = useState('')

  const refresh = useCallback(async () => {
    setContents(await listContents(true))
  }, [])

  useEffect(() => {
    refresh().catch((err) => setError(err.message))
  }, [refresh])

  const openCreate = () => {
    setEditing(null)
    setForm(emptyForm)
    setDialogOpen(true)
  }

  const openEdit = (content) => {
    setEditing(content)
    setForm({
      name: content.name,
      description: content.description || '',
      type: content.type,
      localPath: content.localPath || '',
      durationSeconds: content.durationSeconds ?? '',
    })
    setDialogOpen(true)
  }

  const submit = async () => {
    setError('')
    const payload = {
      name: form.name,
      description: form.description || null,
      type: form.type,
      localPath: form.localPath || null,
      durationSeconds: form.durationSeconds === '' ? null : Number(form.durationSeconds),
    }
    try {
      if (editing) {
        await updateContent(editing.id, payload)
      } else {
        await createContent(payload)
      }
      setDialogOpen(false)
      await refresh()
    } catch (err) {
      setError(err.message)
    }
  }

  const toggleEnabled = async (content) => {
    try {
      await updateContent(content.id, {
        name: content.name,
        description: content.description || null,
        type: content.type,
        localPath: content.localPath || null,
        durationSeconds: content.durationSeconds ?? null,
        enabled: !content.enabled,
      })
      await refresh()
    } catch (err) {
      setError(err.message)
    }
  }

  const remove = async (content) => {
    try {
      await deleteContent(content.id)
      await refresh()
    } catch (err) {
      setError(err.message)
    }
  }

  return (
    <Box>
      <Box sx={{ display: 'flex', alignItems: 'center', mb: 3 }}>
        <Typography variant="h5" sx={{ flexGrow: 1 }}>投放内容</Typography>
        <Button variant="contained" startIcon={<AddIcon />} onClick={openCreate}>
          新增内容
        </Button>
      </Box>
      {error && <Alert severity="error" sx={{ mb: 2 }} onClose={() => setError('')}>{error}</Alert>}
      <Alert severity="info" sx={{ mb: 2 }}>
        此处仅登记内容元数据(名称/本地路径/类型)。媒体文件保留在公司 PC 本地,
        通过 WebRTC 实时推流到房间, 服务器不上传、不存储、不录制任何媒体内容。
      </Alert>
      <Card>
        <CardContent>
          <Table>
            <TableHead>
              <TableRow>
                <TableCell>名称</TableCell>
                <TableCell>类型</TableCell>
                <TableCell>本地路径 / 窗口标识</TableCell>
                <TableCell>时长</TableCell>
                <TableCell>说明</TableCell>
                <TableCell>启用</TableCell>
                <TableCell align="right">操作</TableCell>
              </TableRow>
            </TableHead>
            <TableBody>
              {contents.map((content) => (
                <TableRow key={content.id} hover>
                  <TableCell>{content.name}</TableCell>
                  <TableCell>
                    <Chip size="small" label={typeLabels[content.type] || content.type} />
                  </TableCell>
                  <TableCell sx={{ maxWidth: 280, wordBreak: 'break-all' }}>
                    {content.localPath || '-'}
                  </TableCell>
                  <TableCell>
                    {content.durationSeconds ? `${Math.floor(content.durationSeconds / 60)} 分钟` : '-'}
                  </TableCell>
                  <TableCell sx={{ maxWidth: 200 }}>{content.description || '-'}</TableCell>
                  <TableCell>
                    <Switch checked={!!content.enabled} onChange={() => toggleEnabled(content)} />
                  </TableCell>
                  <TableCell align="right">
                    <Tooltip title="编辑">
                      <IconButton onClick={() => openEdit(content)}><EditIcon /></IconButton>
                    </Tooltip>
                    <Tooltip title="删除(停用)">
                      <IconButton color="error" onClick={() => remove(content)}><DeleteIcon /></IconButton>
                    </Tooltip>
                  </TableCell>
                </TableRow>
              ))}
              {contents.length === 0 && (
                <TableRow>
                  <TableCell colSpan={7}>
                    <Typography color="text.secondary" align="center" sx={{ py: 3 }}>
                      暂无内容, 请先登记要投放的本地内容
                    </Typography>
                  </TableCell>
                </TableRow>
              )}
            </TableBody>
          </Table>
        </CardContent>
      </Card>

      <Dialog open={dialogOpen} onClose={() => setDialogOpen(false)} maxWidth="xs" fullWidth>
        <DialogTitle>{editing ? '编辑内容' : '新增内容'}</DialogTitle>
        <DialogContent sx={{ display: 'flex', flexDirection: 'column', gap: 2, pt: '12px !important' }}>
          <TextField
            label="内容名称"
            value={form.name}
            onChange={(e) => setForm({ ...form, name: e.target.value })}
          />
          <TextField
            select
            label="内容类型"
            value={form.type}
            onChange={(e) => setForm({ ...form, type: e.target.value })}
          >
            {Object.entries(typeLabels).map(([value, label]) => (
              <MenuItem key={value} value={value}>{label}</MenuItem>
            ))}
          </TextField>
          <TextField
            label="本地路径 / 窗口标识"
            placeholder="例: D:\\videos\\产品介绍.mp4"
            value={form.localPath}
            onChange={(e) => setForm({ ...form, localPath: e.target.value })}
          />
          <TextField
            label="时长(秒, 可选)"
            type="number"
            value={form.durationSeconds}
            onChange={(e) => setForm({ ...form, durationSeconds: e.target.value })}
          />
          <TextField
            label="说明(可选)"
            multiline
            minRows={2}
            value={form.description}
            onChange={(e) => setForm({ ...form, description: e.target.value })}
          />
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setDialogOpen(false)}>取消</Button>
          <Button variant="contained" onClick={submit} disabled={!form.name}>
            保存
          </Button>
        </DialogActions>
      </Dialog>
    </Box>
  )
}
