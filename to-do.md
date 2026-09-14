# to-do — finish moving salesforce.imswarnil.com onto Cloudflare Workers

**Status: half done.** The Worker is built, deployed and serving correctly. The
public domain has not moved to it yet.

> ⚠️ This repo is public. Nothing in this file is a secret — no tokens, no
> account IDs, no connection strings. Keep it that way. Where a value is
> needed, the step tells you which command prints it locally.

---

## Why this move exists at all

`salesforce.imswarnil.com` is still being served by **GitHub Pages**, from a
Jekyll build dated **2026-08-16**. That build is stale and cannot be refreshed,
because the repo no longer contains a Jekyll site.

GitHub Pages serves static files only. The current app cannot run there — it
needs a real server for:

- Nitro server routes under `server/api/**`
- Neon Postgres (progress, comments, guestbook, resource submissions)
- httpOnly session cookies (`server/utils/auth.ts`)
- three R2 buckets
- the read-only Salesforce JWT proxy at `/demo-org`

So it targets Cloudflare Workers instead — `nuxt build --preset
cloudflare_module`, see the comment at the top of `nuxt.config.ts`.

That migration was started (the workflow `.github/workflows/deploy.yml` was
added on 2026-09-06) but never completed: the CI run failed in 53 seconds
because the repo had no Cloudflare credentials, and nobody moved the DNS.

---

## What is already done

- **Worker created and deployed** — `salesforce-passport`, live and healthy at
  <https://salesforce-passport.imswarnil.workers.dev>
  - `/` → 200, `/lessons` → 200
  - `/api/demo-org/objects` → 404 `"Demo org is not enabled."` (correct — see
    step 6)
- **R2 consolidated into one bucket** (2026-09-14) — was three root-level
  buckets (`psk-resources`, `psk-guestbook-attachments`, `psk-avatars`, all
  created 2026-09-06). Now a single **`salesforce-passport`** bucket bound as
  **`STORAGE`**, with a key prefix per kind of upload:

  | Prefix | Written by | Read by |
  | --- | --- | --- |
  | `resources/<userId>/<uuid>-<filename>` | `POST /api/resources` | `GET /api/resources/:id` |
  | `guestbook/<userId>/<uuid>.png` | `POST /api/guestbook/drawing` | `GET /api/guestbook/image/:key` |
  | `avatars/<userId>/...` | reserved, unwritten | — |

  The code already wrote those prefixes, so no key changed. All three old
  buckets were empty (0 objects, 0 B — checked twice, immediately before
  deletion) and have been deleted. `psk-avatars` was bound but referenced by no
  code at all. Four handlers now read `env.STORAGE`; deployed and verified.
- **`wrangler.jsonc`** — three edits:
  - added the `salesforce.imswarnil.com` custom-domain route
  - added `"workers_dev": true` (without it, every deploy silently disables the
    workers.dev URL and it starts serving a "There is nothing here yet"
    placeholder)
  - corrected the secrets comment, which named `DATABASE_URL` / `SESSION_SECRET`
    / `SF_*`. The app reads Nuxt's **`NUXT_`-prefixed** names; the unprefixed
    ones are read by nothing.
- **`docs/SETUP_WEB.md` fixed** — it told you to set those same five unprefixed
  secret names. Following it verbatim would have left you with five secrets set
  and a database that never connects, failing silently. Now prefixed, with a
  note explaining why the prefix is load-bearing.
- **All of the above is committed** on `main`, not pushed. See "Pushing" below.

## What is left

Five steps below. **Step 1 is the only real blocker** — everything else is
quick once it's done.

Verified state at the time of writing:

| Check | Result |
| --- | --- |
| `https://salesforce-passport.imswarnil.workers.dev/` | `200` — working |
| `https://salesforce.imswarnil.com/` | still GitHub Pages (`x-github-request-id` present) |
| `npx wrangler secret list` | `[]` — step 3 not done |
| `gh secret list` | empty — step 5 not done |

Nothing here causes an outage. Until step 1, the domain keeps serving the old
Jekyll build.

---

## Step 1 — delete the GitHub Pages DNS records  ⬅ blocker, you must do this

Every deploy currently ends with:

```
Custom domains:
  - Hostname 'salesforce.imswarnil.com' already has externally managed DNS
    records (A, CNAME, etc). Delete them first or try a different hostname.
    [code: 100117]
```

Cloudflare will not let a Worker claim a hostname that already has a
hand-managed DNS record. The record pointing at GitHub Pages has to go first.

1. Sign in at <https://dash.cloudflare.com>
2. Open the **imswarnil.com** zone → **DNS** → **Records**
3. Find the record(s) whose **Name** is `salesforce`. It will be either:
   - four **A** records → `185.199.108.153`, `185.199.109.153`,
     `185.199.110.153`, `185.199.111.153` (GitHub Pages' IPs), or
   - one **CNAME** → `imswarnil.github.io`
4. **Delete every record named `salesforce`.** Leave every other name in the
   zone alone — `imswarnil.com`, `www`, `design`, `creator`, `links`, `nac`,
   `crmanalytics`, `jobseekers`, `trailblazer`, `dev`, `icons`, `theme` and any
   mail records must stay untouched.

You do not need to create a replacement record. Step 2 creates it for you.

> Why you and not me: wrangler's OAuth token on this machine has `zone (read)`
> but no DNS write scope, so it can delete nothing. We tried granting a
> narrower token via the Cloudflare MCP OAuth flow and it bounced through a
> GitHub SSO login and back to a dashboard sign-in page — not worth another lap
> for what is a 30-second dashboard action.

**Verify:**

```bash
dig +short salesforce.imswarnil.com
```

Expect: nothing, or NXDOMAIN. (It may take a minute; Cloudflare's own proxy IPs
`104.21.x` / `172.67.x` disappearing is the signal.)

---

## Step 2 — attach the custom domain

Once step 1 is done:

```bash
cd ~/Swarnil/salesforce.imswarnil.com
npx wrangler deploy
```

Wrangler creates the proxied DNS record and provisions the TLS certificate
itself, because `wrangler.jsonc` declares the route as `custom_domain: true`.

**Expect:** no `Custom domains:` error block, and the output listing both
`https://salesforce.imswarnil.com` and
`https://salesforce-passport.imswarnil.workers.dev`.

**Verify** (the certificate can take a couple of minutes):

```bash
curl -sI https://salesforce.imswarnil.com/ | head -3
curl -sI https://salesforce.imswarnil.com/ | grep -i x-github-request-id
```

The first should return `HTTP/2 200`. The second should return **nothing** — an
`x-github-request-id` header means you are still hitting GitHub Pages.

---

## Step 3 — set the two Worker secrets

`npx wrangler secret list` currently returns `[]`. Without these the site still
renders (lessons are file-based content), but every database-backed feature —
accounts, progress, comments, guestbook, resource submissions — fails.

Run each and paste the value at the prompt:

```bash
cd ~/Swarnil/salesforce.imswarnil.com

npx wrangler secret put NUXT_DATABASE_URL
npx wrangler secret put NUXT_SESSION_SECRET
```

- `NUXT_DATABASE_URL` — the Neon connection string. It is already in your local
  `.env` (gitignored); copy it from there.
- `NUXT_SESSION_SECRET` — generate a **fresh** one rather than reusing the dev
  value:

  ```bash
  openssl rand -base64 32
  ```

  Production should not share a session secret with dev. There are no existing
  production sessions to invalidate, so now is the free moment to do this.

**Names matter.** They must carry the `NUXT_` prefix — that is how Nuxt
overrides `runtimeConfig` at runtime (`nuxt.config.ts`, `runtimeConfig`
block). A secret named `DATABASE_URL` would be read by nothing and the failure
is silent. (`docs/SETUP_WEB.md` used to give the unprefixed names; that is
fixed, so the doc and this file now agree.)

**Verify:**

```bash
npx wrangler secret list
```

Expect both names listed. Then confirm the database actually answers — load the
site and check that a page backed by Neon renders rather than erroring.

If the schema was never applied to this Neon database:

```bash
pnpm run db:migrate
```

Safe to re-run — every statement in `db/migrations/*.sql` is `if not exists`,
and there is no migration-tracking table.

---

## Step 4 — turn off GitHub Pages for this repo

Pages is still configured on the repo (`cname: salesforce.imswarnil.com`, TLS
cert issued, expires 2026-11-21). Leaving it on means two services believe they
own the same hostname. It cannot win once step 1 is done, but it should not be
left armed.

```bash
gh api -X DELETE repos/imswarnil/Passport-Seva-Kendra-Salesforce/pages
```

**Do this only after step 2 verifies green.** It is the one step that is
awkward to undo quickly — re-enabling Pages means re-issuing the TLS
certificate, which is not instant.

**Verify:**

```bash
gh api repos/imswarnil/Passport-Seva-Kendra-Salesforce/pages
```

Expect `404` / `Not Found`.

---

## Step 5 — fix the CI deploy workflow

`.github/workflows/deploy.yml` deploys on every push to `main` that touches the
app. Its only run so far (2026-09-06) failed:

```
[ERROR] In a non-interactive environment, it's necessary to set a
CLOUDFLARE_API_TOKEN environment variable for wrangler to work.
```

`gh secret list` returns nothing. Both repo secrets are missing.

1. Create an API token at
   <https://dash.cloudflare.com/profile/api-tokens> → **Create Token**.
   Use the **Edit Cloudflare Workers** template, or a custom token with:
   - `Account` → `Workers Scripts` → **Edit**
   - `Account` → `Workers R2 Storage` → **Edit**
   - `Zone` → `DNS` → **Edit** on `imswarnil.com` (only needed if you want CI to
     be able to re-create the custom domain; skip it otherwise)
2. Get your account ID — it is printed by:

   ```bash
   npx wrangler whoami
   ```

3. Set both secrets (each prompts for the value, so nothing lands in shell
   history):

   ```bash
   cd ~/Swarnil/salesforce.imswarnil.com
   gh secret set CLOUDFLARE_API_TOKEN
   gh secret set CLOUDFLARE_ACCOUNT_ID
   ```

**Verify:**

```bash
gh secret list
gh workflow run deploy.yml
gh run watch
```

Note: the Worker secrets from step 3 are **not** set by CI. They live on the
Worker and are set once with `wrangler secret put`. The workflow only needs the
two credentials above.

---

## Step 6 — optional: the `/demo-org` proxy

Currently **off**, and that is the correct default for a fresh state.

In your local `.env`, `NUXT_SF_CLIENT_ID`, `NUXT_SF_USERNAME` and
`NUXT_SF_PRIVATE_KEY` are all **empty**, and
`NUXT_PUBLIC_DEMO_ORG_ENABLED=false`. In production `/api/demo-org/*` returns
`404 "Demo org is not enabled."` — verified on the deployed Worker.

Leave it that way unless you deliberately want the live org proxy exposed.
`docs/SETUP_ORG.md` is required reading first — per this repo's own CLAUDE.md,
that feature is "a live credential to the real org sitting behind a public
website", and its safety rests on three things staying true:

- the integration user has **only** `PSK_Demo_Read_Only` assigned
- the Connected App `PSK_Demo_Proxy` stays `AdminApproved`, never `AllUsers`
- `server/utils/demo-org-allowlist.ts` — not the permission set — stays the
  authority on what is queryable

To enable later: set the three `NUXT_SF_*` secrets with `wrangler secret put`,
plus `NUXT_PUBLIC_DEMO_ORG_ENABLED=true`, then redeploy.

---

## Also worth doing, unrelated to this migration

`force-app/main/default/connectedApps/N8N.connectedApp-meta.xml` has a real
OAuth Consumer Key committed in a public repo. Rotate it: App Manager → N8N →
Manage Consumer Details → rotate, then redeploy the metadata with the new value
scrubbed. Flagged in this repo's CLAUDE.md; not caused by this migration.

---

## Pushing

The three changed files are **committed locally but not pushed**. Pushing
`wrangler.jsonc` to `main` matches a path filter in
`.github/workflows/deploy.yml` and triggers a deploy run, which will **fail**
until step 5 adds the two repo secrets. Harmless — a red X on the commit, no
effect on anything live — but it is why the push was left to you.

Either push now and accept one red run, or do step 5 first and push into a
working pipeline:

```bash
cd ~/Swarnil/salesforce.imswarnil.com
git push
```

## If it goes wrong — rollback

Before step 4, rollback is trivial: re-create the `salesforce` DNS records
pointing at GitHub Pages (CNAME → `imswarnil.github.io`, proxied) and the old
Jekyll build serves again.

After step 4, you would also need to re-enable Pages on the repo and wait for a
new TLS certificate.

The Worker itself is independent of all of this and stays reachable at
`salesforce-passport.imswarnil.workers.dev` throughout — that is what
`workers_dev: true` guarantees.

---

## Quick reference

| Thing | Value |
| --- | --- |
| Worker name | `salesforce-passport` |
| Preview URL | <https://salesforce-passport.imswarnil.workers.dev> |
| Target domain | `salesforce.imswarnil.com` |
| Cloudflare account | `Swarnil` (`npx wrangler whoami`) |
| Repo | `imswarnil/Passport-Seva-Kendra-Salesforce` |
| Worker secrets needed | `NUXT_DATABASE_URL`, `NUXT_SESSION_SECRET` |
| Repo secrets needed | `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID` |
| R2 bucket | `salesforce-passport`, bound as `STORAGE` |
| Build | `pnpm run build` (`nuxt build --preset cloudflare_module`) |
| Deploy | `npx wrangler deploy` |
| Docs | `docs/SETUP_WEB.md`, `docs/SETUP_ORG.md` |
