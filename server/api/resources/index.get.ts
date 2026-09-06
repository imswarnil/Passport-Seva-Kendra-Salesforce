export default defineEventHandler(async () => {
  const sql = useDb()
  const rows = await sql`
    select r.id, r.title, r.description, r.url, r.r2_key as "r2Key", r.created_at as "createdAt",
           u.display_name as "submittedBy"
    from resource_submissions r
    join users u on u.id = r.user_id
    where r.status = 'approved'
    order by r.created_at desc
  `
  return {
    resources: rows.map(r => ({
      ...r,
      // Never leak the raw R2 key — the file lives behind /api/resources/:id.
      r2Key: undefined,
      fileUrl: r.r2Key ? `/api/resources/${r.id}` : null
    }))
  }
})
