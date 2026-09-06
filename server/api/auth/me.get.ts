// A "who am I" check the frontend polls on load — always 200, never a 401
// gate, so guests get `{ user: null }` rather than an error.
export default defineEventHandler(async (event) => {
  const user = await getSessionUser(event)
  return { user }
})
