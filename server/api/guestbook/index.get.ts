const PAGE_SIZE = 20

export default defineEventHandler(async (event) => {
  const query = getQuery(event)
  const page = Math.max(1, Number.parseInt(String(query.page ?? '1'), 10) || 1)
  const offset = (page - 1) * PAGE_SIZE

  const sql = useDb()
  const rows = await sql`
    select id, display_name as "displayName", message,
      image_key is not null as "hasImage",
      case when image_key is not null then split_part(image_key, '/', -1) else null end as "imageFile",
      created_at as "createdAt"
    from guestbook_entries
    where hidden = false
    order by created_at desc
    limit ${PAGE_SIZE + 1} offset ${offset}
  `

  const hasMore = rows.length > PAGE_SIZE
  const entries = rows.slice(0, PAGE_SIZE).map(r => ({
    ...r,
    // The .png suffix is stripped so the client just does
    // `/api/guestbook/image/${imageId}` — see image/[key].get.ts.
    imageId: r.imageFile ? String(r.imageFile).replace(/\.png$/, '') : null,
    imageFile: undefined
  }))

  return { entries, page, pageSize: PAGE_SIZE, hasMore, hasPrev: page > 1 }
})
