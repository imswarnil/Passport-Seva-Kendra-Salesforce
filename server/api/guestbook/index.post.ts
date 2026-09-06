import { z } from 'zod'

const schema = z.object({
  displayName: z.string().trim().min(1).max(80).optional(),
  message: z.string().trim().min(1).max(1000),
  // Set only by POST /api/guestbook/drawing just before this call, never
  // typed by hand — validated as that route's own key shape (not trusted
  // as an arbitrary R2 key) so this can't be used to attach someone else's
  // upload to your entry.
  imageKey: z.string().regex(/^guestbook\/[a-f0-9-]+\/[a-f0-9-]+\.png$/).optional()
})

// Open to anonymous visitors as well as signed-in users — a real guestbook,
// not gated. displayName is required for guests; signed-in users' own name
// is used instead, so they can't spoof another display name.
//
// No IP-based rate limiting here — enforcing that at the Worker would need
// a Cloudflare Rate Limiting rule or a KV request counter, neither of which
// is wired up in this repo yet. Length caps are the only abuse guard so far.
export default defineEventHandler(async (event) => {
  const user = await getSessionUser(event)
  const parsed = schema.safeParse(await readBody(event))
  if (!parsed.success) {
    throw createError({ statusCode: 422, statusMessage: 'Message must be 1-1000 characters.' })
  }

  const displayName = user?.displayName ?? parsed.data.displayName
  if (!displayName) {
    throw createError({ statusCode: 422, statusMessage: 'A display name is required.' })
  }

  // A drawing can only be attached by the same user drawing.post.ts issued
  // the key to — the regex alone doesn't prove ownership, just shape.
  const imageKey = parsed.data.imageKey
  if (imageKey && !imageKey.startsWith(`guestbook/${user?.id}/`)) {
    throw createError({ statusCode: 403, statusMessage: 'That drawing does not belong to you.' })
  }

  const sql = useDb()
  const [entry] = await sql`
    insert into guestbook_entries (user_id, display_name, message, image_key)
    values (${user?.id ?? null}, ${displayName}, ${parsed.data.message}, ${imageKey ?? null})
    returning id, display_name as "displayName", message, created_at as "createdAt"
  `
  return { entry }
})
