import type { H3Event } from 'h3'

const SESSION_COOKIE = 'psk_session'
const SESSION_DAYS = 30
const PBKDF2_ITERATIONS = 210_000

function toBase64(bytes: Uint8Array) {
  return btoa(String.fromCharCode(...bytes))
}
function fromBase64(b64: string) {
  return Uint8Array.from(atob(b64), c => c.charCodeAt(0))
}

async function sha256Hex(input: string) {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(input))
  return [...new Uint8Array(digest)].map(b => b.toString(16).padStart(2, '0')).join('')
}

// PBKDF2-SHA256 rather than bcrypt/argon2 — no native addon, works unmodified
// on Workers' Web Crypto implementation.
export async function hashPassword(password: string) {
  const salt = crypto.getRandomValues(new Uint8Array(16))
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(password), 'PBKDF2', false, ['deriveBits'])
  const bits = await crypto.subtle.deriveBits(
    { name: 'PBKDF2', salt, iterations: PBKDF2_ITERATIONS, hash: 'SHA-256' },
    key,
    256
  )
  return `pbkdf2$${PBKDF2_ITERATIONS}$${toBase64(salt)}$${toBase64(new Uint8Array(bits))}`
}

export async function verifyPassword(password: string, stored: string) {
  const [scheme, iterationsRaw, saltB64, hashB64] = stored.split('$')
  if (scheme !== 'pbkdf2') return false
  const iterations = Number(iterationsRaw)
  const salt = fromBase64(saltB64)
  const expected = fromBase64(hashB64)
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(password), 'PBKDF2', false, ['deriveBits'])
  const bits = new Uint8Array(await crypto.subtle.deriveBits({ name: 'PBKDF2', salt, iterations, hash: 'SHA-256' }, key, 256))
  if (bits.length !== expected.length) return false
  let diff = 0
  for (let i = 0; i < bits.length; i++) diff |= bits[i] ^ expected[i]
  return diff === 0
}

// The cookie holds a random token; only its SHA-256 is stored in `sessions`,
// so a leaked database dump doesn't hand out working session tokens.
export async function createSession(event: H3Event, userId: string) {
  const token = toBase64(crypto.getRandomValues(new Uint8Array(32)))
  const tokenHash = await sha256Hex(token)
  const expiresAt = new Date(Date.now() + SESSION_DAYS * 24 * 60 * 60 * 1000)

  const sql = useDb()
  await sql`
    insert into sessions (id, user_id, expires_at)
    values (${tokenHash}, ${userId}, ${expiresAt.toISOString()})
  `

  setCookie(event, SESSION_COOKIE, token, {
    httpOnly: true,
    secure: true,
    sameSite: 'lax',
    path: '/',
    maxAge: SESSION_DAYS * 24 * 60 * 60
  })
}

export async function destroySession(event: H3Event) {
  const token = getCookie(event, SESSION_COOKIE)
  if (token) {
    const sql = useDb()
    await sql`delete from sessions where id = ${await sha256Hex(token)}`
  }
  deleteCookie(event, SESSION_COOKIE, { path: '/' })
}

export interface SessionUser {
  id: string
  email: string
  displayName: string
}

export async function getSessionUser(event: H3Event): Promise<SessionUser | null> {
  const token = getCookie(event, SESSION_COOKIE)
  if (!token) return null

  const sql = useDb()
  const rows = await sql`
    select u.id, u.email, u.display_name as "displayName"
    from sessions s
    join users u on u.id = s.user_id
    where s.id = ${await sha256Hex(token)} and s.expires_at > now()
  `
  return (rows[0] as SessionUser) ?? null
}

export async function requireUser(event: H3Event): Promise<SessionUser> {
  const user = await getSessionUser(event)
  if (!user) throw createError({ statusCode: 401, statusMessage: 'Sign in required.' })
  return user
}
