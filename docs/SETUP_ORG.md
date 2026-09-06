# Setting up the live, read-only org demo

This is the checklist for turning on `/demo-org` on the public site — a real,
live, browsable view into the actual Passport Seva Kendra dev org, through a
dedicated integration user that can only ever read six non-PII objects. It's
off by default (`NUXT_PUBLIC_DEMO_ORG_ENABLED=false`) and every route 404s
until you've done all of this.

**Read this whole file before doing any of it.** The security of this feature
rests entirely on three things staying true forever: the integration user has
*only* `PSK_Demo_Read_Only` assigned, the Connected App stays `AdminApproved`
(never `AllUsers`), and `server/utils/demo-org-allowlist.ts` stays the
authority on what fields are queryable — not whatever the permission set
would technically allow if you ever edit it by hand in Setup.

## 1. Create the dedicated integration user

Setup → Users → New User. Give it:
- A real (or role-account) email you control, since Salesforce will send a
  verification link to it.
- **A license that includes API access and can be assigned a permission
  set** — a Salesforce Platform or full Salesforce license works; a
  Community/Experience Cloud external user does **not** work for JWT Bearer,
  because the JWT `sub` claim must resolve to an *internal* running user
  context.
- **No Profile beyond the minimum** (e.g. "Minimum Access - Salesforce" if
  your org has it, or the least-privileged standard profile available).
- Do not check any admin/API-enabled-by-default profile.

## 2. Assign exactly one permission set

```bash
sf org assign permset --name PSK_Demo_Read_Only --target-org <your-org> --on-behalf-of <the-integration-user's-username>
```

Or via Setup → Permission Set Assignments. **Never assign this user any other
permission set or a profile with object/field write access.** Come back and
re-check this periodically — it's the actual security boundary between the
public internet and your real org, more than any code in this repo.

## 3. Deploy the Connected App metadata

```bash
sf project deploy start --metadata ConnectedApp:PSK_Demo_Proxy --target-org <your-org>
```

## 4. Generate the JWT keypair

```bash
openssl req -x509 -sha256 -nodes -days 3650 -newkey rsa:2048 \
  -keyout server.key -out server.crt \
  -subj "/CN=psk-demo-proxy"

# server/utils/sf.ts expects PKCS#8. If server.key starts with
# "-----BEGIN RSA PRIVATE KEY-----" (PKCS#1) rather than
# "-----BEGIN PRIVATE KEY-----", convert it:
openssl pkcs8 -topk8 -nocrypt -in server.key -out server.pkcs8.key
```

`server.crt` is not secret — it's the public half, going *into* Salesforce.
`server.key` / `server.pkcs8.key` are the whole ballgame — never commit them,
never paste them anywhere but the Worker secret in step 7. Delete the local
files once step 7 is done, or keep them somewhere like a password manager if
you'll need to rotate.

## 5. Upload the cert and get the Consumer Key

Setup → App Manager → find **"PSK Demo Proxy (read-only, JWT)"** → dropdown →
**View**. Click **Edit Policies**, set **Permitted Users** to "Admin approved
users are pre-authorized" (should already be set from the metadata), and
under the OAuth section upload `server.crt` as the certificate. Save. Back on
the View page, click **Manage Consumer Details** (may require a verification
code) to reveal the **Consumer Key** — that's `NUXT_SF_CLIENT_ID`.

## 6. Pre-authorize the integration user

Still on the Connected App: **Manage** → **Edit Policies**, and under
"Permitted Users" assign the `PSK_Demo_Read_Only` permission set (or the
integration user's profile, if you went that route) so the app doesn't
require an interactive OAuth consent screen — JWT Bearer needs this to work
headlessly.

## 7. Set the Worker secrets

```bash
wrangler secret put NUXT_SF_CLIENT_ID          # from step 5
wrangler secret put NUXT_SF_USERNAME           # the integration user's username
wrangler secret put NUXT_SF_PRIVATE_KEY        # the full contents of server.pkcs8.key, PEM headers included
wrangler secret put NUXT_DATABASE_URL          # if not already set — see main SETUP.md
```

For local dev, put the same values in `.env` (see `.env.example`) — most
`.env` loaders preserve a multi-line quoted value, so paste the PEM with its
real newlines inside `NUXT_SF_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\n...`.

Then set:
```bash
wrangler secret put NUXT_PUBLIC_DEMO_ORG_ENABLED   # value: true
```
(and `NUXT_PUBLIC_DEMO_ORG_ENABLED=true` in `.env` for local dev).

## 8. Verify before trusting it

- Hit `/api/demo-org/objects` — should list exactly six objects.
- Hit `/api/demo-org/Citizen__c/records` — should 404, since `Citizen__c` is
  intentionally not in the allowlist even though it exists in the org.
- Confirm in Setup → the integration user's page that **Permission Set
  Assignments** shows only `PSK_Demo_Read_Only`.

## Ongoing responsibility

This is a live credential to a real org sitting behind a public website.
Rotate the keypair (repeat steps 4–7) if you ever suspect the private key
leaked. If you ever need to kill the feature fast, either flip
`NUXT_PUBLIC_DEMO_ORG_ENABLED` back to `false` and redeploy, or — faster,
no redeploy needed — go to Setup → App Manager → PSK Demo Proxy → **Edit
Policies** → set Permitted Users to "Admin approved" with *no* users/permission
sets assigned, which revokes access immediately at the Salesforce side
regardless of what the Worker thinks its config is.

## What I'm not fully certain of — verify against a real org before flipping this on

- The exact JWT claim shape and `RSASSA-PKCS1-v1_5` Web Crypto usage in
  `server/utils/sf.ts` follows the documented Salesforce JWT Bearer spec, but
  it has not been exercised against a live org from this environment (no `sf`
  CLI or org auth was available here to test it end-to-end). Test steps 1–8
  against a real sandbox/dev org before ever setting
  `NUXT_PUBLIC_DEMO_ORG_ENABLED=true` on a production Worker.
- Whether your org's My Domain / login URL is `login.salesforce.com` or a
  custom domain affects `NUXT_SF_LOGIN_URL` — use your actual My Domain URL
  (e.g. `https://your-domain.my.salesforce.com`) if `login.salesforce.com`
  redirects fail the JWT assertion's `aud` check.
