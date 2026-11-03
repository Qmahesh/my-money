import { Route, Routes } from 'react-router-dom'
import Layout from './components/Layout'
import RequireAuth from './components/RequireAuth'
import Home from './pages/Home'
import Login from './pages/Login'
import Placeholder from './pages/Placeholder'
import Settings from './pages/Settings'

export default function App() {
  return (
    <Routes>
      <Route path="/login" element={<Login />} />
      <Route
        element={
          <RequireAuth>
            <Layout />
          </RequireAuth>
        }
      >
        <Route index element={<Home />} />
        <Route path="add" element={<Placeholder titleKey="nav.add" />} />
        <Route path="bills" element={<Placeholder titleKey="nav.bills" />} />
        <Route path="accounts" element={<Placeholder titleKey="nav.accounts" />} />
        <Route path="reports" element={<Placeholder titleKey="nav.reports" />} />
        <Route path="settings" element={<Settings />} />
      </Route>
    </Routes>
  )
}
