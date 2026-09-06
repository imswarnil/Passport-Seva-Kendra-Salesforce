import { defineCollection, defineContentConfig, z } from '@nuxt/content'

// Folder depth/number is the URL and the curriculum order — same convention
// as jobseekers.imswarnil.com, no separate manifest to keep in sync.
//   content/2.data-model/1.data-modeling.md  →  /data-model/data-modeling
// `prefix: '/'` drops the "lessons" segment the source folder name would
// otherwise contribute — lesson URLs are flat (/data-model/data-modeling),
// matching every top-level nav item's own module slug rather than nesting
// under a shared /lessons/ root. The catalogue itself still lives at
// /lessons (app/pages/lessons/index.vue), a separate, ordinary page.
export default defineContentConfig({
  collections: {
    lessons: defineCollection({
      type: 'page',
      // Not `**/*.md` — that glob excludes each module's `.navigation.yml`,
      // which is what supplies the sidebar's per-module title/icon (see
      // LessonSidebar.vue). Nuxt Content merges a `.navigation.yml` into its
      // directory's nav node by matching its `stem`, but only for files this
      // collection actually indexes in the first place.
      source: { include: 'lessons/**', prefix: '/' },
      schema: z.object({
        title: z.string(),
        // Optional — a lesson's own frontmatter always sets these, but
        // `.navigation.yml` (a folder's nav title/icon, not a real page)
        // only sets `title`/`icon` and must still validate against this
        // same schema since it lives in the same source glob.
        description: z.string().optional(),
        minutes: z.number().optional(),
        kind: z.enum(['lesson', 'reference', 'project']).default('lesson'),
        objects: z.array(z.string()).optional(), // Salesforce objects this lesson touches
        icon: z.string().optional() // set on .navigation.yml files only
      })
    }),
    pages: defineCollection({
      type: 'page',
      source: 'pages/**/*.md',
      schema: z.object({
        title: z.string(),
        description: z.string()
      })
    })
  }
})
