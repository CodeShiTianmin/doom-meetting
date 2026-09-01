import { useState } from 'react'
import {
  Button, CircularProgress, Dialog, DialogActions, DialogContent, DialogContentText, DialogTitle,
} from '@mui/material'

/**
 * 危险操作二次确认弹窗; onConfirm 可返回 Promise, 期间按钮进入 loading 并禁止重复提交
 */
export default function ConfirmDialog({
  open,
  title = '确认操作',
  content,
  confirmText = '确认',
  cancelText = '取消',
  confirmColor = 'error',
  onConfirm,
  onClose,
}) {
  const [submitting, setSubmitting] = useState(false)

  const handleConfirm = async () => {
    if (submitting) return
    setSubmitting(true)
    try {
      await onConfirm?.()
    } catch (err) {
      // 错误提示由调用方负责(onConfirm 内部已处理), 此处仅避免未捕获异常
      console.error('[ConfirmDialog] confirm failed', err)
    } finally {
      setSubmitting(false)
      onClose?.()
    }
  }

  return (
    <Dialog open={open} onClose={submitting ? undefined : onClose} maxWidth="xs" fullWidth>
      <DialogTitle>{title}</DialogTitle>
      {content && (
        <DialogContent>
          {typeof content === 'string' ? <DialogContentText>{content}</DialogContentText> : content}
        </DialogContent>
      )}
      <DialogActions sx={{ px: 3, pb: 2 }}>
        <Button onClick={onClose} disabled={submitting}>{cancelText}</Button>
        <Button
          variant="contained"
          color={confirmColor}
          onClick={handleConfirm}
          disabled={submitting}
          startIcon={submitting ? <CircularProgress size={16} color="inherit" /> : null}
        >
          {confirmText}
        </Button>
      </DialogActions>
    </Dialog>
  )
}
