import { z } from 'zod'

const schema = z.object({
  email: z.string().trim().toLowerCase().email(),
  password: z.string().min(1)
})

export default defineEventHandler(async (event) => {
  const body = schema.safeParse(await readBody(event))
  if (!body.success) {
    throw createError({ statusCode: 422, statusMessage: 'Enter an email and password.' })
  }
  const { email, password } = body.data

  const sql = useDb()
  const [row] = await sql`
    select id, email, display_name as "displayName", password_hash as "passwordHash"
    from users where email = ${email}
  `
  // Same error for "no such user" and "wrong password" — don't let the
  // response shape confirm which emails have accounts.
  if (!row || !(await verifyPassword(password, row.passwordHash))) {
    throw createError({ statusCode: 401, statusMessage: 'Incorrect email or password.' })
  }

  await createSession(event, row.id)
  return { user: { id: row.id, email: row.email, displayName: row.displayName } }
})
