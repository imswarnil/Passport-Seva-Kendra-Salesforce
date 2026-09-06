import { z } from 'zod'

const schema = z.object({
  category: z.enum(['lesson-idea', 'bug', 'demo-org', 'other']),
  body: z.string().trim().min(1).max(2000)
})

// One-way: no GET endpoint. Suggestions are reviewed by querying Neon
// directly, not through an admin UI — anonymous submission is allowed on
// purpose (user_id is nullable) since feedback shouldn't require an account.
export default defineEventHandler(async (event) => {
  const user = await getSessionUser(event)
  const parsed = schema.safeParse(await readBody(event))
  if (!parsed.success) {
    throw createError({ statusCode: 422, statusMessage: parsed.error.issues[0]?.message ?? 'Invalid input.' })
  }

  const sql = useDb()
  await sql`
    insert into suggestions (user_id, category, body)
    values (${user?.id ?? null}, ${parsed.data.category}, ${parsed.data.body})
  `
  return { ok: true }
})
