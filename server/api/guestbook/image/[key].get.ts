// Streams a guestbook doodle back out. The route param is only the UUID
// filename segment — the fixed `guestbook/` prefix and the user-id folder
// are reconstructed server-side from the DB row, not trusted from the URL,
// so this can never be used to read an arbitrary R2 key.
export default defineEventHandler(async (event) => {
  const key = getRouterParam(event, 'key')
  if (!key || !/^[a-f0-9-]+$/.test(key)) throw createError({ statusCode: 404, statusMessage: 'Not found.' })

  const sql = useDb()
  const [row] = await sql`
    select image_key as "imageKey" from guestbook_entries
    where image_key like ${'%/' + key + '.png'} and hidden = false
  `
  if (!row?.imageKey) throw createError({ statusCode: 404, statusMessage: 'Not found.' })

  const bucket = event.context.cloudflare?.env?.GUESTBOOK_ATTACHMENTS
  if (!bucket) throw createError({ statusCode: 500, statusMessage: 'Drawing storage is not configured.' })

  const object = await bucket.get(row.imageKey)
  if (!object) throw createError({ statusCode: 404, statusMessage: 'Not found.' })

  setHeader(event, 'content-type', 'image/png')
  setHeader(event, 'cache-control', 'public, max-age=31536000, immutable')
  return object.body
})
