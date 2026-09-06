// Streams a resource's R2 attachment back out — only once it's been
// approved, so an unmoderated upload can never be fetched by guessing/
// enumerating ids.
export default defineEventHandler(async (event) => {
  const id = getRouterParam(event, 'id')
  const sql = useDb()
  const [row] = await sql`
    select r2_key as "r2Key" from resource_submissions where id = ${id} and status = 'approved'
  `
  if (!row?.r2Key) throw createError({ statusCode: 404, statusMessage: 'Not found.' })

  const bucket = event.context.cloudflare?.env?.RESOURCES
  if (!bucket) throw createError({ statusCode: 500, statusMessage: 'Resource storage is not configured.' })

  const object = await bucket.get(row.r2Key)
  if (!object) throw createError({ statusCode: 404, statusMessage: 'Not found.' })

  setHeader(event, 'content-type', object.httpMetadata?.contentType ?? 'application/octet-stream')
  return object.body
})
