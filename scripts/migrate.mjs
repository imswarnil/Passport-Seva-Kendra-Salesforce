// Applies db/migrations/*.sql, in filename order, against NUXT_DATABASE_URL
// (or DATABASE_URL). Uses `pg` (a plain TCP connection) rather than the
// runtime's @neondatabase/serverless HTTP driver — this is a one-off Node
// script, not a Worker, so there's no edge-runtime constraint pushing us
// toward the HTTP driver here. No migration-tracking table on purpose — this
// project is small enough that "re-run the one new file by hand" beats a
// framework; every statement uses `if not exists`, so re-running an
// already-applied file is a no-op rather than an error.
import { readdir, readFile } from 'node:fs/promises'
import pg from 'pg'

const url = process.env.NUXT_DATABASE_URL ?? process.env.DATABASE_URL
if (!url) {
  console.error('Set NUXT_DATABASE_URL (or DATABASE_URL) — see .env.example.')
  process.exit(1)
}

const client = new pg.Client({ connectionString: url })
await client.connect()

const dir = new URL('../db/migrations/', import.meta.url)
const files = (await readdir(dir)).filter(f => f.endsWith('.sql')).sort()

for (const file of files) {
  console.log(`Applying ${file}...`)
  const text = await readFile(new URL(file, dir), 'utf8')
  await client.query(text)
}

await client.end()
console.log(`Done — applied ${files.length} migration file(s).`)
