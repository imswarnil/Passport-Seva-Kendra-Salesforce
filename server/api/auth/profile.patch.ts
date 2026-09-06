import { z } from 'zod'

const schema = z.object({
  displayName: z.string().trim().min(1).max(80)
})

// The only editable profile field today — email/password changes aren't
// built yet (would need re-verification and a re-auth flow respectively,
// both bigger than this one-column rename).
export default defineEventHandler(async (event) => {
  const user = await requireUser(event)
  const parsed = schema.safeParse(await readBody(event))
  if (!parsed.success) {
    throw createError({ statusCode: 422, statusMessage: 'Display name must be 1-80 characters.' })
  }

  const sql = useDb()
  const [updated] = await sql`
    update users set display_name = ${parsed.data.displayName}, updated_at = now()
    where id = ${user.id}
    returning id, email, display_name as "displayName"
  `
  return { user: updated }
})
