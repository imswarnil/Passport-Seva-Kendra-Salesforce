interface AuthUser {
  id: string
  email: string
  displayName: string
}

// useState, not a plain ref — shared across components and SSR-safe, same
// pattern Nuxt expects for "current user" style global state.
export function useAuth() {
  const user = useState<AuthUser | null>('auth:user', () => null)
  const loaded = useState<boolean>('auth:loaded', () => false)

  async function refresh() {
    const { user: current } = await $fetch<{ user: AuthUser | null }>('/api/auth/me')
    user.value = current
    loaded.value = true
    return current
  }

  async function signup(payload: { email: string; password: string; displayName: string }) {
    const { user: created } = await $fetch<{ user: AuthUser }>('/api/auth/signup', { method: 'POST', body: payload })
    user.value = created
    return created
  }

  async function login(payload: { email: string; password: string }) {
    const { user: signedIn } = await $fetch<{ user: AuthUser }>('/api/auth/login', { method: 'POST', body: payload })
    user.value = signedIn
    return signedIn
  }

  async function logout() {
    await $fetch('/api/auth/logout', { method: 'POST' })
    user.value = null
  }

  async function updateProfile(payload: { displayName: string }) {
    const { user: updated } = await $fetch<{ user: AuthUser }>('/api/auth/profile', { method: 'PATCH', body: payload })
    user.value = updated
    return updated
  }

  if (import.meta.client && !loaded.value) refresh()

  return { user, loaded, refresh, signup, login, logout, updateProfile }
}
