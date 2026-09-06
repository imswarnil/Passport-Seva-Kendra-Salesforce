// Public — no auth required to read comments.
export default defineEventHandler(async (event) => {
  const slug = getRouterParam(event, 'slug', { decode: true })
  if (!slug) throw createError({ statusCode: 400, statusMessage: 'Missing lesson slug.' })

  const sql = useDb()
  const rows = await sql`
    select c.id, c.body, c.created_at as "createdAt", u.display_name as "displayName"
    from comments c
    join users u on u.id = c.user_id
    where c.lesson_slug = ${slug} and c.hidden = false
    order by c.created_at asc
  `
  return { comments: rows }
})
