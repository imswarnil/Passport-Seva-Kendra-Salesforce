import { z } from 'zod'

const schema = z.object({
  email: z.string().trim().toLowerCase().email(),
  password: z.string().min(8).max(200),
  displayName: z.string().trim().min(1).max(80)
})

export default defineEventHandler(async (event) => {
  const body = schema.safeParse(await readBody(event))
  if (!body.success) {
    throw createError({ statusCode: 422, statusMessage: body.error.issues[0]?.message ?? 'Invalid input.' })
  }
  const { email, password, displayName } = body.data

  const sql = useDb()
  const existing = await sql`select id from users where email = ${email}`
  if (existing.length > 0) {
    throw createError({ statusCode: 409, statusMessage: 'An account with that email already exists.' })
  }

  const passwordHash = await hashPassword(password)
  const [user] = await sql`
    insert into users (email, password_hash, display_name)
    values (${email}, ${passwordHash}, ${displayName})
    returning id, email, display_name as "displayName"
  `

  await createSession(event, user.id)
  return { user }
})
