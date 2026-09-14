import { z } from 'zod'

const schema = z.object({
  // A data URL from <canvas>.toDataURL('image/png') — small doodles only.
  dataUrl: z.string().startsWith('data:image/png;base64,')
})

const MAX_BYTES = 500_000 // a hand-drawn doodle PNG this small is plenty

// Requires sign-in — not because the guestbook message itself does, but
// because an anonymous, unmoderated image upload to a public bucket is a
// meaningfully bigger abuse surface than an anonymous line of text.
export default defineEventHandler(async (event) => {
  const user = await requireUser(event)
  const parsed = schema.safeParse(await readBody(event))
  if (!parsed.success) {
    throw createError({ statusCode: 422, statusMessage: 'A PNG data URL is required.' })
  }

  const base64 = parsed.data.dataUrl.slice('data:image/png;base64,'.length)
  const bytes = Buffer.from(base64, 'base64')
  if (bytes.byteLength > MAX_BYTES) {
    throw createError({ statusCode: 413, statusMessage: 'Drawing is too large (max 500KB).' })
  }

  const bucket = event.context.cloudflare?.env?.STORAGE
  if (!bucket) throw createError({ statusCode: 500, statusMessage: 'Drawing storage is not configured.' })

  const key = `guestbook/${user.id}/${crypto.randomUUID()}.png`
  await bucket.put(key, bytes, { httpMetadata: { contentType: 'image/png' } })

  return { imageKey: key }
})
