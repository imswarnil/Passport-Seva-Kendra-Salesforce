import { z } from 'zod'

const schema = z.object({ body: z.string().trim().min(1).max(2000) })

export default defineEventHandler(async (event) => {
  const user = await requireUser(event)
  const slug = getRouterParam(event, 'slug', { decode: true })
  if (!slug) throw createError({ statusCode: 400, statusMessage: 'Missing lesson slug.' })

  const parsed = schema.safeParse(await readBody(event))
  if (!parsed.success) {
    throw createError({ statusCode: 422, statusMessage: 'Comment must be 1-2000 characters.' })
  }

  const sql = useDb()
  const [comment] = await sql`
    insert into comments (lesson_slug, user_id, body)
    values (${slug}, ${user.id}, ${parsed.data.body})
    returning id, body, created_at as "createdAt"
  `
  return { comment: { ...comment, displayName: user.displayName } }
})
