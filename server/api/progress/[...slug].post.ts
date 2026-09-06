// Catch-all, not `[slug]` — lesson slugs are multi-segment content paths
// (e.g. "data-model/data-modeling"), and a single dynamic segment would only
// ever capture the last part.
export default defineEventHandler(async (event) => {
  const user = await requireUser(event)
  const slug = getRouterParam(event, 'slug', { decode: true })
  if (!slug) throw createError({ statusCode: 400, statusMessage: 'Missing lesson slug.' })

  const sql = useDb()
  await sql`
    insert into lesson_progress (user_id, lesson_slug)
    values (${user.id}, ${slug})
    on conflict (user_id, lesson_slug) do nothing
  `
  return { ok: true }
})
