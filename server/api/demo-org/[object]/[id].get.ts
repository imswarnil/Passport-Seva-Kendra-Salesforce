import { DEMO_ORG_OBJECTS, assertAllowedObject, checkRateLimit } from '~~/server/utils/demo-org-allowlist'
import { sfGet } from '~~/server/utils/sf'

// Same allowlist as records.get.ts, applied to a single record by Id via
// SOQL rather than the raw sobject-row REST endpoint, so the field list stays
// enforced here too (the raw endpoint would return every field on the object).
export default defineEventHandler(async (event) => {
  const config = useRuntimeConfig()
  if (!config.public.demoOrgEnabled) {
    throw createError({ statusCode: 404, statusMessage: 'Demo org is not enabled.' })
  }
  checkRateLimit(event)

  const object = getRouterParam(event, 'object')!
  assertAllowedObject(object)
  const id = getRouterParam(event, 'id')!

  // Salesforce Ids are 15/18-char alphanumerics — reject anything else before
  // it goes anywhere near a SOQL string.
  if (!/^[a-zA-Z0-9]{15,18}$/.test(id)) {
    throw createError({ statusCode: 400, statusMessage: 'Invalid record Id.' })
  }

  const fields = DEMO_ORG_OBJECTS[object].join(', ')
  const soql = `SELECT ${fields} FROM ${object} WHERE Id = '${id}' LIMIT 1`
  const result = await sfGet(`/query?q=${encodeURIComponent(soql)}`) as { records: unknown[] }

  if (!result.records.length) {
    throw createError({ statusCode: 404, statusMessage: 'Record not found (or not visible to the demo user).' })
  }
  return result.records[0]
})
