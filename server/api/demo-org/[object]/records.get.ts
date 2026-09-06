import { DEMO_ORG_OBJECTS, assertAllowedObject, checkRateLimit } from '~~/server/utils/demo-org-allowlist'
import { sfGet } from '~~/server/utils/sf'

const PAGE_SIZE = 20
// Salesforce SOQL OFFSET is capped at 2000 regardless of who's asking —
// clamp to that rather than letting a page param walk past it into an error.
const MAX_OFFSET = 2000

// LIMIT/OFFSET only, a hardcoded field list per object, and no
// request-supplied fields/filters/ordering — the entire point of this route
// is that nothing about the query is attacker- or even caller-controlled
// beyond which of the six allowlisted objects to look at and which page.
export default defineEventHandler(async (event) => {
  const config = useRuntimeConfig()
  if (!config.public.demoOrgEnabled) {
    throw createError({ statusCode: 404, statusMessage: 'Demo org is not enabled.' })
  }
  checkRateLimit(event)

  const object = getRouterParam(event, 'object')!
  assertAllowedObject(object)

  const query = getQuery(event)
  const page = Math.max(1, Number.parseInt(String(query.page ?? '1'), 10) || 1)
  const offset = Math.min((page - 1) * PAGE_SIZE, MAX_OFFSET)

  const fields = DEMO_ORG_OBJECTS[object].join(', ')
  // Fetch one extra row to know whether a next page exists without a
  // separate COUNT() query.
  const soql = `SELECT ${fields} FROM ${object} ORDER BY CreatedDate DESC LIMIT ${PAGE_SIZE + 1} OFFSET ${offset}`
  const result = await sfGet(`/query?q=${encodeURIComponent(soql)}`) as { records: unknown[] }

  const hasMore = result.records.length > PAGE_SIZE
  return {
    records: result.records.slice(0, PAGE_SIZE),
    page,
    pageSize: PAGE_SIZE,
    hasMore,
    hasPrev: page > 1
  }
})
