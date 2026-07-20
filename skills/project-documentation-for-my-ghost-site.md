---
name: project-documentation-for-my-ghost-site
description: >
  How to document any project Swarnil works on and publish it to imswarnil.com as
  a Ghost "project" with an ongoing build-log. Read this whenever the task is
  "document what we did / what I learned and post it to my site", or "add a log to
  my project", or "create a project on imswarnil.com". Produces or updates a single
  self-contained Ghost import JSON in `dummy-content/`.
---

# Documenting a project on imswarnil.com

This is Swarnil's standing process. **Any project** he works on — in any repo, with
Claude or otherwise — gets a running build-log that publishes to
**imswarnil.com** as a *Project* with nested *build-log* entries. The unit of work
is: _finish a session → write down what we did and what we learned → append it as a
new log entry in the project's Ghost import JSON._

Everything below is grounded in how the live site actually works. Follow it exactly;
don't invent new tag schemes or route shapes.

---

## 0. TL;DR loop (do this every session)

1. Open (or create) the project's import file: `dummy-content/<project>.json`.
2. If the project is new → add **one container post** (the project brief).
3. Append **one `#project-detail` post** = this session's log ("Part N — …").
4. Write it as real learning: **task → what I did → what broke → how I fixed it →
   notes for next time.** Not marketing copy.
5. Validate the JSON, then import it in Ghost Admin (see §7).
6. Commit.

> One JSON file per project. It holds the brief **and** every log entry. It is
> re-importable at any time (Ghost upserts by id/slug).

---

## 1. How imswarnil.com works (the parts you need)

The site is a **tag-driven Ghost theme**. Content type is decided by an **internal
`#hash-*` tag**, and `routes.yaml` turns each hash-tag into a collection with its own
URL and template. You never pick a template directly — you pick a tag.

**Projects specifically** use a *container + children* pattern:

| Role | Tag it carries | Lives at |
|------|----------------|----------|
| **Project** (the brief / landing card) | public project tag **as primary** + internal `#project` | `/projects/{post-slug}/` |
| **Build-log entry** (one per session) | the **same public project tag as primary** + internal `#project-detail` | `/projects/{project-tag}/{post-slug}/` |

So a build-log entry **nests under its project** because its *primary* (first) tag is
the project's public tag. Get the primary tag wrong and the nesting breaks.

Other collections follow the exact same shape (container tag / child tag), in case a
project is better modelled as one of these:

| Content | Container tag | Child tag |
|---------|---------------|-----------|
| Projects | `#project` | `#project-detail` |
| Courses | `#course` | `#lesson` |
| Web series | `#webseries` | `#episode` |
| Travel | `#trip` | `#travel` |
| Guides | `#guide` | `#guide-content` |
| Flat collections | `#video`, `#product`, `#shop`, `#blog`, `#timeline`, `#changelog`, `#newsletter`, `#prompt`, `#snippet`, `#experience`, `#docs` | — |

For documenting engineering work, **always use `#project` / `#project-detail`.**

### Tags to include on a project

- **Public project tag** — the project's name, e.g. `Passport Seva Kendra`
  (slug `passport-seva-kendra`). This is the identity of the whole project. It is the
  **primary (first, sort_order 0)** tag on the container *and* on every log entry.
- **`#project`** — internal, on the container only. Puts it in the projects collection.
- **`#project-detail`** — internal, on every log entry only.
- **`#skill-*`** — internal skill tags on the container, e.g. `#skill-Salesforce`,
  `#skill-Apex`, `#skill-Flow`. These surface the tech used.
- **A public topic tag** — broad theme, e.g. `Salesforce`, so it also shows on topic pages.

`#hash-*` (internal) tags are **deduped by slug on import** — reuse the same slug
(`hash-project`, `hash-project-detail`, `hash-skill-salesforce`) across files and Ghost
merges them. Public tags are per-project and unique.

### The `dummy-content/` folder

One self-contained Ghost export per module (`project.json`, `course.json`, …). Your
project files live here too. See `dummy-content/README.md` for the full list. Each file
is a normal Ghost export and can be imported independently and repeatedly.

---

## 2. The Ghost import JSON format

A file is a Ghost export with three arrays under `db[0].data`:

```jsonc
{
 "db": [
  {
   "meta": { "exported_on": 1784628000000, "version": "5.0.0" },
   "data": {
    "posts":      [ /* the brief + every log entry */ ],
    "tags":       [ /* project tag, #project, #project-detail, #skill-*, topic */ ],
    "posts_tags": [ /* which tags each post has, WITH sort_order */ ]
   }
  }
 ]
}
```

### Post object

```jsonc
{
  "id": "700000000000000000000101",           // 24-hex fake ObjectId, unique in-file
  "title": "Part 3 — Security, sharing & DPDP-safe PII",
  "slug": "psk-3-security-pii",                // unique; child slugs kebab, prefixed
  "mobiledoc": "…stringified mobiledoc…",       // body — see below
  "feature_image": "https://picsum.photos/seed/psk-3-security-pii/1200/800",
  "featured": 0,                                // 1 only on the container, if you want
  "type": "post",
  "status": "published",
  "custom_excerpt": "One-line summary shown on cards.",
  "created_at": "2026-07-21T12:00:00.000Z",
  "updated_at": "2026-07-21T12:00:00.000Z",
  "published_at": "2026-07-21T12:00:00.000Z"    // controls order; log entries ascend
}
```

### mobiledoc (the body)

The body is a **stringified** mobiledoc doc wrapping one HTML card. This is the shape
the theme's demo content uses:

```
{"version":"0.3.1","atoms":[],"cards":[["html",{"html":"<p>…your HTML…</p>"}]],"markups":[],"sections":[[10,0],[1,"p",[]]]}
```

Because the HTML sits inside a JSON string inside another JSON string, **do not
hand-escape it.** Generate the file with a tiny Node script (see §4).

### posts_tags — order matters

```jsonc
{ "post_id": "<post id>", "tag_id": "<tag id>", "sort_order": 0 }
```

- `sort_order: 0` is the **primary tag** — it MUST be the public project tag.
- Container order: `[projectTag(0), #project(1), #skill-*(2..), topic(last)]`.
- Log-entry order: `[projectTag(0), #project-detail(1)]`.

### id convention (avoid collisions)

Use a **fixed 24-hex prefix per project** so ids never clash with other files. PSK uses
`7000000000000000000001xx`. Pick a new prefix per project (`7100…`, `7200…`, …).
For the shared internal tags, **reuse the canonical ids/slugs** so they dedupe:
`#project` → slug `hash-project`, `#project-detail` → slug `hash-project-detail`.

---

## 3. Writing a good log entry (the content)

Each `#project-detail` post is **one work session**. Title them `Part N — <what>`.
Structure the HTML body as:

- **One-line context** — what this session set out to do.
- **`<h2>` What I did** — the concrete steps/commands.
- **`<h2>` What broke / what was tricky** — the real problem (this is the valuable part).
- **`<h2>` How I fixed it** — the resolution, with a `<pre><code>…</code></pre>` if code.
- **`<blockquote>` the lesson** — the one sentence you'd tell your past self.

Write to teach, not to impress. Include real commands, real errors, real fixes.
`custom_excerpt` = a one-line summary for the card.

The **container** post is different — it's the evergreen **brief**: what the project is,
the design philosophy, what exists today, and links (GitHub repo, live/org URL). Update
it as the project grows; keep it as the front door.

---

## 4. Generator script (use this — don't escape by hand)

Write a throwaway Node script, run it, delete it. Template:

```js
const fs = require('fs');
const mobiledoc = (html) => JSON.stringify({
  version:"0.3.1", atoms:[], cards:[["html",{html}]], markups:[], sections:[[10,0],[1,"p",[]]]
});

// Reuse canonical internal tags so Ghost dedupes them across files:
const PROJECT   = { id:"000000000000000000000102", name:"#project",        slug:"hash-project",        visibility:"internal", description:"" };
const DETAIL    = { id:"000000000000000000000136", name:"#project-detail", slug:"hash-project-detail", visibility:"internal", description:"" };
// Per-project public + skill tags (unique ids, pick a fresh 24-hex prefix):
const PROJ_TAG  = { id:"71000000000000000000000a", name:"My Project", slug:"my-project", visibility:"public",
                    description:"One-line project description.", feature_image:"https://picsum.photos/seed/my-project/1200/800" };
const TOPIC     = { id:"71000000000000000000000b", name:"Salesforce", slug:"salesforce", visibility:"public", description:"" };

const posts = [], posts_tags = [];
const add = (p, tags) => {
  posts.push({ id:p.id, title:p.title, slug:p.slug, mobiledoc:mobiledoc(p.html),
    feature_image:p.feature_image||`https://picsum.photos/seed/${p.slug}/1200/800`,
    featured:p.featured?1:0, type:"post", status:"published", custom_excerpt:p.excerpt,
    created_at:p.date, updated_at:p.date, published_at:p.date });
  tags.forEach((t,i)=>posts_tags.push({ post_id:p.id, tag_id:t.id, sort_order:i }));
};

// Container (brief) — primary tag first:
add({ id:"710000000000000000000100", title:"My Project — Brief", slug:"my-project", featured:true,
      date:"2026-07-21T09:00:00.000Z", excerpt:"What this project is, in one line.",
      html:`<p>Brief…</p><h2 id="links">Links</h2><ul><li><a href="https://github.com/…">Code</a></li></ul>` },
     [PROJ_TAG, PROJECT, TOPIC]);

// Log entry — primary tag first, then #project-detail:
add({ id:"710000000000000000000101", title:"Part 1 — Kickoff", slug:"my-project-1-kickoff",
      date:"2026-07-21T10:00:00.000Z", excerpt:"What I did and learned today.",
      html:`<p>Context…</p><h2>What I did</h2><ul><li>…</li></ul><blockquote>The lesson.</blockquote>` },
     [PROJ_TAG, DETAIL]);

fs.writeFileSync(__dirname + "/dummy-content/my-project.json",
  JSON.stringify({ db:[{ meta:{ exported_on:1784628000000, version:"5.0.0" }, data:{ posts, tags:[PROJ_TAG, PROJECT, DETAIL, TOPIC], posts_tags } }] }, null, 1) + "\n");
console.log("wrote", posts.length, "posts");
```

**To append a later session:** re-open the script (or the JSON), add one more `add(...)`
call / one more post + its two `posts_tags` rows with the next `Part N`, a new unique
id (bump the last hex), and a later `published_at`. Regenerate and re-import.

`Date.now()` etc. are fine in your own local script; the `exported_on` value is
cosmetic — any epoch-ms integer works.

---

## 5. Starting a brand-new project

1. Copy the generator template above → set a fresh id prefix, project tag name/slug,
   skill tags, topic, GitHub/live/org links.
2. Write the container brief + `Part 1`.
3. Output to `dummy-content/<project-slug>.json`.
4. Add a row for it to `dummy-content/README.md`'s file table.

## 6. Validate before importing

```bash
node -e "const d=require('./dummy-content/<file>.json');const P=d.db[0].data;\
P.posts.forEach(p=>JSON.parse(p.mobiledoc));\
const c=P.posts.find(p=>P.posts_tags.some(t=>t.post_id===p.id&&t.sort_order===1&&t.tag_id==='000000000000000000000102'));\
console.log('posts',P.posts.length,'tags',P.tags.length,'container',c&&c.slug)"
```

Checklist:
- [ ] Every `mobiledoc` parses.
- [ ] Container has `#project` (id `…102`); each log entry has `#project-detail` (id `…136`).
- [ ] Every post's `sort_order: 0` tag is the **public project tag** (not a hash tag).
- [ ] All `id`s and `slug`s unique within the file.
- [ ] Log entries have ascending `published_at`.

## 7. Publish

Ghost Admin → **Settings → Import/Export → Import** → pick `dummy-content/<file>.json`.
Re-importing the same file updates existing posts by id (safe to do after each session).
Then it appears on **/projects/** and at **/projects/<project-slug>/**.

## 8. Commit

```bash
git add dummy-content/<file>.json dummy-content/README.md
git commit -m "docs(project): <project> — add Part N build-log"
```

---

## Reference: the PSK example

`dummy-content/psk.json` is a complete, working instance of everything above:
container brief *"Passport Seva Kendra — Salesforce Platform"* (`#project`) + three
`#project-detail` build-logs nesting at `/projects/passport-seva-kendra/…`, id prefix
`7000…`. Copy its shape for the next project.
