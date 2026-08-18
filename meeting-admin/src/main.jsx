import React from 'react'
import ReactDOM from 'react-dom/client'
import { BrowserRouter } from 'react-router-dom'
import { ThemeProvider, createTheme } from '@mui/material/styles'
import CssBaseline from '@mui/material/CssBaseline'
import App from './App.jsx'

const theme = createTheme({
  palette: {
    mode: 'light',
    primary: { main: '#4f46e5' },
    secondary: { main: '#06b6a4' },
    error: { main: '#ef4444' },
    warning: { main: '#f59e0b' },
    success: { main: '#10b981' },
    background: { default: '#eef1f8', paper: '#ffffff' },
    text: { primary: '#1e2340', secondary: '#6b7291' },
  },
  shape: { borderRadius: 14 },
  typography: {
    fontFamily: '"PingFang SC", "Microsoft YaHei", "Helvetica Neue", Arial, sans-serif',
    h4: { fontWeight: 800 },
    h5: { fontWeight: 800, letterSpacing: '-0.01em' },
    h6: { fontWeight: 700 },
    button: { fontWeight: 600 },
  },
  components: {
    MuiCard: {
      styleOverrides: {
        root: {
          boxShadow: '0 6px 24px rgba(30, 41, 120, 0.07)',
          border: '1px solid rgba(79, 70, 229, 0.06)',
          transition: 'box-shadow .25s ease, transform .25s ease',
        },
      },
    },
    MuiButton: {
      styleOverrides: {
        root: { textTransform: 'none', fontWeight: 600, borderRadius: 10 },
        containedPrimary: {
          background: 'linear-gradient(135deg, #4f46e5 0%, #6d5ef5 100%)',
          boxShadow: '0 4px 14px rgba(79, 70, 229, 0.35)',
        },
      },
    },
    MuiChip: {
      styleOverrides: { root: { fontWeight: 600 } },
    },
    MuiTableCell: {
      styleOverrides: {
        head: {
          fontWeight: 700,
          color: '#6b7291',
          background: '#f7f8fd',
          borderBottom: 'none',
        },
      },
    },
    MuiDialog: {
      styleOverrides: { paper: { borderRadius: 18 } },
    },
  },
})

ReactDOM.createRoot(document.getElementById('root')).render(
  <React.StrictMode>
    <ThemeProvider theme={theme}>
      <CssBaseline />
      <BrowserRouter>
        <App />
      </BrowserRouter>
    </ThemeProvider>
  </React.StrictMode>,
)
