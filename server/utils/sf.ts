// JWT Bearer flow against Salesforce, implemented with Web Crypto rather than
// the `jsonwebtoken` npm package — that package shells out to Node's `crypto`
// module in ways that don't run on Workers. Everything here is spec-standard
// RS256 JWT signing, just hand-rolled for the edge runtime.
//
// Read this alongside docs/SETUP_ORG.md and force-app's
// connectedApps/PSK_Demo_Proxy.connectedApp-meta.xml + permissionsets/
// PSK_Demo_Read_Only.permissionset-meta.xml — those three pieces plus this
// file are the entire security boundary between the public demo and the real
// org: the Connected App's AdminApproved policy decides WHO can get a token,
// this file gets that token, and the permission set decides what the token
// can see. server/api/demo-org/** then adds a fourth layer (an object/field
// allowlist) on top, deliberately not trusting the permission set alone.

interface SfAuth {
  accessToken: string
  instanceUrl: string
  // Salesforce doesn't hand back an expiry for the JWT bearer grant; treat
  // the cached token as good for 25 minutes (session timeout defaults are
  // usually 2+ hours) and just re-mint before then. This is a module-level
  // variable, so it's reused across requests within one Worker isolate and
  // re-fetched from scratch whenever the isolate is recycled — that's fine,
  // the JWT bearer grant is cheap and rate limits are per-org, not per-token.
}

let cached: (SfAuth & { fetchedAt: number }) | undefined
const TOKEN_LIFETIME_MS = 25 * 60 * 1000

function base64url(bytes: ArrayBuffer | Uint8Array) {
  const arr = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes)
  let str = ''
  for (const b of arr) str += String.fromCharCode(b)
  return btoa(str).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
}

function pemToPkcs8(pem: string): ArrayBuffer {
  const stripped = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, '')
    .replace(/-----END PRIVATE KEY-----/, '')
    .replace(/\s+/g, '')
  const raw = atob(stripped)
  const bytes = new Uint8Array(raw.length)
  for (let i = 0; i < raw.length; i++) bytes[i] = raw.charCodeAt(i)
  return bytes.buffer
}

async function signJwt(clientId: string, username: string, loginUrl: string, privateKeyPem: string) {
  const header = { alg: 'RS256', typ: 'JWT' }
  const now = Math.floor(Date.now() / 1000)
  const claims = {
    iss: clientId,
    sub: username,
    aud: loginUrl,
    exp: now + 180 // JWT bearer assertions must be short-lived; this is not the session lifetime
  }

  const encodedHeader = base64url(new TextEncoder().encode(JSON.stringify(header)))
  const encodedClaims = base64url(new TextEncoder().encode(JSON.stringify(claims)))
  const signingInput = `${encodedHeader}.${encodedClaims}`

  // Requires a PKCS#8 PEM ("-----BEGIN PRIVATE KEY-----"). If your `openssl
  // genrsa`/`req` output is PKCS#1 ("-----BEGIN RSA PRIVATE KEY-----"),
  // convert with:
  //   openssl pkcs8 -topk8 -nocrypt -in server.key -out server.pkcs8.key
  const key = await crypto.subtle.importKey(
    'pkcs8',
    pemToPkcs8(privateKeyPem),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign']
  )

  const signature = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, new TextEncoder().encode(signingInput))
  return `${signingInput}.${base64url(signature)}`
}

async function fetchAccessToken(): Promise<SfAuth> {
  const config = useRuntimeConfig()
  if (!config.sfClientId || !config.sfUsername || !config.sfPrivateKey) {
    throw createError({ statusCode: 503, statusMessage: 'Demo org is not configured — see docs/SETUP_ORG.md.' })
  }

  const assertion = await signJwt(config.sfClientId, config.sfUsername, config.sfLoginUrl, config.sfPrivateKey)

  const response = await fetch(`${config.sfLoginUrl}/services/oauth2/token`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion
    })
  })

  if (!response.ok) {
    const body = await response.text()
    throw createError({ statusCode: 502, statusMessage: `Salesforce JWT auth failed: ${body}` })
  }

  const json = await response.json() as { access_token: string, instance_url: string }
  return { accessToken: json.access_token, instanceUrl: json.instance_url }
}

export async function getSfAuth(): Promise<SfAuth> {
  if (cached && Date.now() - cached.fetchedAt < TOKEN_LIFETIME_MS) return cached
  const auth = await fetchAccessToken()
  cached = { ...auth, fetchedAt: Date.now() }
  return cached
}

const API_VERSION = 'v61.0'

// Every call site passes its own hardcoded, already-validated path — this
// helper does not sanitize input, because it should never see unsanitized
// input. The allowlisting happens in server/api/demo-org/**, before this is
// ever called.
export async function sfGet(path: string) {
  let auth = await getSfAuth()
  let response = await fetch(`${auth.instanceUrl}/services/data/${API_VERSION}${path}`, {
    headers: { Authorization: `Bearer ${auth.accessToken}` }
  })

  if (response.status === 401) {
    // Token may have been revoked/expired early — one retry with a fresh one.
    cached = undefined
    auth = await getSfAuth()
    response = await fetch(`${auth.instanceUrl}/services/data/${API_VERSION}${path}`, {
      headers: { Authorization: `Bearer ${auth.accessToken}` }
    })
  }

  if (!response.ok) {
    throw createError({ statusCode: 502, statusMessage: `Salesforce API error (${response.status}): ${await response.text()}` })
  }
  return response.json()
}
