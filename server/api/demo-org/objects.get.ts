import { DEMO_ORG_OBJECTS, checkRateLimit } from '~~/server/utils/demo-org-allowlist'

// Lists the (fixed, small) set of objects the public demo exposes, with their
// allowed field list — the frontend uses this to build the object picker and
// knows in advance which columns it can render, no describe() call needed.
export default defineEventHandler((event) => {
  const config = useRuntimeConfig()
  if (!config.public.demoOrgEnabled) {
    throw createError({ statusCode: 404, statusMessage: 'Demo org is not enabled.' })
  }
  checkRateLimit(event)

  return Object.entries(DEMO_ORG_OBJECTS).map(([object, fields]) => ({ object, fields }))
})
