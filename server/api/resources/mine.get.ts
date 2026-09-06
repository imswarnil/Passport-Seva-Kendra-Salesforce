// The signed-in user's own submissions, any status — used by /dashboard so
// someone can see "pending" review state for what they submitted.
export default defineEventHandler(async (event) => {
  const user = await requireUser(event)
  const sql = useDb()
  const rows = await sql`
    select id, title, description, url, status, created_at as "createdAt"
    from resource_submissions
    where user_id = ${user.id}
    order by created_at desc
  `
  return { resources: rows }
})
