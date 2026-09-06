import { neon } from '@neondatabase/serverless'

let cached: ReturnType<typeof neon> | undefined

// The Neon HTTP driver, not a pooled TCP connection — each query is one
// fetch(), which is what makes this safe to call from a Worker's stateless
// request handler without a connection-pooling story of our own.
export function useDb() {
  if (!cached) {
    const config = useRuntimeConfig()
    if (!config.databaseUrl) {
      throw createError({ statusCode: 500, statusMessage: 'DATABASE_URL is not configured — see SETUP.md.' })
    }
    cached = neon(config.databaseUrl)
  }
  return cached
}
