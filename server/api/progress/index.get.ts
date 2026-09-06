// Degrades gracefully for guests — an empty list, not a 401 — since the
// lesson pages show progress UI regardless of sign-in state.
export default defineEventHandler(async (event) => {
  const user = await getSessionUser(event)
  if (!user) return { completedSlugs: [] }

  const sql = useDb()
  const rows = await sql`select lesson_slug from lesson_progress where user_id = ${user.id}`
  return { completedSlugs: rows.map(r => r.lesson_slug as string) }
})
