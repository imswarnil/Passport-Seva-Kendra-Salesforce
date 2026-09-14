# Setting up the web platform (Neon + Cloudflare)

This covers everything needed to run the site locally and deploy it — accounts,
progress, comments, guestbook, resources, suggestions. For the separate
read-only Salesforce demo-org proxy, see [SETUP_ORG.md](SETUP_ORG.md).

Nothing here has been provisioned yet — no Neon project, no Cloudflare
Worker/R2 buckets, no wrangler login. This is the checklist to do that.

## 1. Install dependencies

```bash
nvm use 22        # or any Node 22+
corepack enable    # gets you the pinned pnpm from package.json
pnpm install       # generates pnpm-lock.yaml — commit it once it exists
```

## 2. Create the Neon database

1. Create a project at [neon.tech](https://neon.tech) (free tier is plenty to start).
2. Copy the pooled connection string from the Neon console.
3. `cp .env.example .env` and paste it into `NUXT_DATABASE_URL`.
4. Generate a session secret: `openssl rand -base64 32` → `NUXT_SESSION_SECRET`.
5. Apply the schema:
   ```bash
   pnpm run db:migrate
   ```
   (Re-run this any time a new file lands in `db/migrations/`.)

## 3. Run it locally

```bash
pnpm run dev
```

`/demo-org` will 404 until the Salesforce side is set up — see SETUP_ORG.md —
`NUXT_PUBLIC_DEMO_ORG_ENABLED` defaults to `false`.

## 4. Cloudflare account setup

```bash
npx wrangler login
```

Create the three R2 buckets `wrangler.jsonc` already declares bindings for:

```bash
npx wrangler r2 bucket create psk-resources
npx wrangler r2 bucket create psk-guestbook-attachments
npx wrangler r2 bucket create psk-avatars
```

Set the Worker secrets (production values — separate from your local `.env`):

```bash
npx wrangler secret put NUXT_DATABASE_URL
npx wrangler secret put NUXT_SESSION_SECRET
# The three SF secrets are only needed once SETUP_ORG.md's demo-org flow is ready:
npx wrangler secret put NUXT_SF_CLIENT_ID
npx wrangler secret put NUXT_SF_USERNAME
npx wrangler secret put NUXT_SF_PRIVATE_KEY
```

The `NUXT_` prefix is not decoration — it is how Nuxt overrides the
`runtimeConfig` block in `nuxt.config.ts` at runtime, and it is why
`.env.example` prefixes every name. A secret set as `DATABASE_URL` is read by
nothing, and the failure is silent: the site still renders, but every
database-backed feature fails.

## 5. Deploy

```bash
pnpm run deploy       # build + wrangler deploy, from your machine
```

Or push to `main` — `.github/workflows/deploy.yml` does the same thing in CI,
given two repo secrets: `CLOUDFLARE_API_TOKEN` (scoped to Workers
Scripts:Edit + R2 Storage:Edit for this account) and `CLOUDFLARE_ACCOUNT_ID`.

## 6. DNS

Point `salesforce.imswarnil.com` at the deployed Worker with a Cloudflare
Custom Domain (Workers & Pages → your worker → Settings → Domains & Routes),
which also gets you the TLS certificate automatically.

## Moderation note

`comments`, `guestbook_entries`, and `resource_submissions` all ship with a
soft-moderation column (`hidden` / `status`) but no admin UI yet — for now,
moderate by connecting to Neon directly (`psql "$DATABASE_URL"` or the Neon
console's SQL editor) and updating rows by hand. A `/admin` moderation page is
a reasonable next lesson-adjacent feature to add once there's real traffic to
moderate.
