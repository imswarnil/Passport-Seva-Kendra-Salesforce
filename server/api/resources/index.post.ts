import { z } from 'zod'

const fieldsSchema = z.object({
  title: z.string().trim().min(1).max(150),
  description: z.string().trim().min(1).max(1000),
  url: z.string().trim().url().optional()
})

// Accepts EITHER JSON `{title, description, url}` OR multipart form data
// with the same fields plus an optional `file` part — the file goes to the
// RESOURCES R2 bucket, not both an attachment and a url are required.
// Status starts 'pending': nothing here appears on the public list
// (GET /api/resources only returns status='approved') until moderated by
// hand via a direct Neon query — there's no admin UI for this yet.
export default defineEventHandler(async (event) => {
  const user = await requireUser(event)
  const sql = useDb()
  const contentType = getHeader(event, 'content-type') ?? ''

  let fields: z.infer<typeof fieldsSchema>
  let r2Key: string | null = null

  if (contentType.includes('multipart/form-data')) {
    const parts = await readMultipartFormData(event)
    if (!parts) throw createError({ statusCode: 422, statusMessage: 'Empty form submission.' })

    const raw: Record<string, string> = {}
    const filePart = parts.find(p => p.name === 'file' && p.filename)
    for (const part of parts) {
      if (part.name && part.name !== 'file' && part.data) raw[part.name] = part.data.toString('utf8')
    }
    const parsed = fieldsSchema.safeParse(raw)
    if (!parsed.success) {
      throw createError({ statusCode: 422, statusMessage: parsed.error.issues[0]?.message ?? 'Invalid input.' })
    }
    fields = parsed.data

    if (filePart) {
      // NuxtHub/Nitro cloudflare_module convention: bindings are exposed on
      // event.context.cloudflare.env. Confirm this once `wrangler dev` runs —
      // it's the standard shape for the cloudflare_module preset, but worth
      // a sanity check against whatever Nitro version ends up installed.
      const bucket = event.context.cloudflare?.env?.RESOURCES
      if (!bucket) throw createError({ statusCode: 500, statusMessage: 'Resource storage is not configured.' })
      r2Key = `resources/${user.id}/${crypto.randomUUID()}-${filePart.filename}`
      await bucket.put(r2Key, filePart.data, {
        httpMetadata: { contentType: filePart.type ?? 'application/octet-stream' }
      })
    }
  } else {
    const parsed = fieldsSchema.safeParse(await readBody(event))
    if (!parsed.success) {
      throw createError({ statusCode: 422, statusMessage: parsed.error.issues[0]?.message ?? 'Invalid input.' })
    }
    fields = parsed.data
  }

  if (!fields.url && !r2Key) {
    throw createError({ statusCode: 422, statusMessage: 'Provide a url or attach a file.' })
  }

  const [resource] = await sql`
    insert into resource_submissions (user_id, title, description, url, r2_key)
    values (${user.id}, ${fields.title}, ${fields.description}, ${fields.url ?? null}, ${r2Key})
    returning id, title, description, url, status, created_at as "createdAt"
  `
  return { resource }
})
