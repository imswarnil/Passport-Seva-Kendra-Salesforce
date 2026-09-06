<script setup lang="ts">
// Flat lesson URLs — /data-model/data-modeling, not /lessons/data-model/data-modeling
// (content.config.ts sets the `lessons` collection's prefix to '/' for
// exactly this). This file is a root-level catch-all rather than living
// under pages/lessons/, so it only ever wins for paths nothing more specific
// already claims — Nuxt/vue-router always prefers a static route
// (/login, /demo-org, /lessons itself, …) over a [...slug] catch-all,
// regardless of file order.
const route = useRoute()
const path = `/${(route.params.slug as string[]).join('/')}`

const { data: page } = await useAsyncData(`lesson-${path}`, () => queryCollection('lessons').path(path).first())
// The `.navigation.yml` that sets each module's sidebar title/icon lives in
// this same collection (see content.config.ts) but is never a real page —
// it never sets `description`, so this also catches someone guessing its
// synthetic path.
if (!page.value || !page.value.description) {
  throw createError({ statusCode: 404, statusMessage: 'Lesson not found' })
}

const { data: surround } = await useAsyncData(`lesson-surround-${path}`, () =>
  queryCollectionItemSurroundings('lessons', path)
)

const toc = computed(() => (page.value as any)?.body?.toc?.links ?? [])

// Best-effort — `stem` preserves the numbered folder/file names Nuxt
// Content strips from the URL (e.g. "2.data-model/1.data-modeling"), so
// this reconstructs the actual source path under content/lessons/.
const editUrl = computed(() => {
  const stem = (page.value as any)?.stem
  const filePath = stem ? `${stem}.md` : `${path.replace(/^\//, '')}.md`
  return `https://github.com/imswarnil/Passport-Seva-Kendra-Salesforce/edit/main/content/lessons/${filePath}`
})

useSeoMeta({
  title: page.value.title,
  description: page.value.description
})

useHead({
  script: [{
    type: 'application/ld+json',
    innerHTML: JSON.stringify({
      '@context': 'https://schema.org',
      '@type': 'LearningResource',
      name: page.value.title,
      description: page.value.description,
      learningResourceType: page.value.kind,
      timeRequired: `PT${page.value.minutes}M`,
      isPartOf: { '@type': 'Course', name: 'Salesforce Passport' },
      isAccessibleForFree: true,
      url: `https://salesforce.imswarnil.com${path}`
    })
  }]
})
</script>

<template>
  <LessonsShell>
    <article class="lesson">
      <header class="lesson-header">
        <div class="lesson-meta-row">
          <p class="lesson-meta">{{ page.minutes }} min · {{ page.kind }}</p>
          <ShareButton :title="page.title" :text="page.description" />
        </div>
        <h1>{{ page.title }}</h1>
        <p class="lesson-description">{{ page.description }}</p>
        <div v-if="page.objects?.length" class="lesson-objects">
          <ObjectRef v-for="obj in page.objects" :key="obj" :name="obj" />
        </div>
      </header>

      <ContentRenderer :value="page" class="prose" />

      <a :href="editUrl" target="_blank" rel="noopener" class="edit-page-link">
        <Icon name="lucide:pencil" /> Edit this page on GitHub
      </a>

      <CommentThread :lesson-slug="path.replace(/^\//, '')" />

      <nav class="lesson-nav">
        <NuxtLink v-if="surround?.[0]" :to="surround[0].path" class="lesson-nav-link prev">
          <Icon name="lucide:arrow-left" />
          <span class="lesson-nav-text">
            <span class="lesson-nav-label">Previous</span>
            <span>{{ surround[0].title }}</span>
          </span>
        </NuxtLink>
        <span v-else />
        <NuxtLink v-if="surround?.[1]" :to="surround[1].path" class="lesson-nav-link next">
          <span class="lesson-nav-text">
            <span class="lesson-nav-label">Next</span>
            <span>{{ surround[1].title }}</span>
          </span>
          <Icon name="lucide:arrow-right" />
        </NuxtLink>
      </nav>
    </article>

    <template v-if="toc.length" #toc>
      <LessonToc :links="toc" />
    </template>
  </LessonsShell>
</template>

<style scoped>
.lesson { max-width: 50rem; }
.lesson-meta-row { display: flex; align-items: center; justify-content: space-between; gap: 1rem; }
.lesson-meta {
  display: flex;
  align-items: center;
  gap: 0.4rem;
  font-size: 0.8rem;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  color: var(--fg-faint);
  margin: 0;
}
.lesson-description { font-size: 1.1rem; }
.lesson-objects { display: flex; gap: 0.4rem; flex-wrap: wrap; margin-top: 1rem; }

.edit-page-link {
  display: inline-flex;
  align-items: center;
  gap: 0.4rem;
  margin-top: 2rem;
  font-size: 0.85rem;
  color: var(--fg-subtle);
  text-decoration: none;
}
.edit-page-link:hover { color: var(--fg-default); }

.lesson-nav {
  display: flex;
  justify-content: space-between;
  gap: 1rem;
  margin-top: 3rem;
  padding-top: 2rem;
  border-top: 1px solid var(--line-subtle);
}
.lesson-nav-link {
  display: flex;
  align-items: center;
  gap: 0.6rem;
  text-decoration: none;
  color: var(--fg-default);
  max-width: 48%;
  padding: 0.6rem 0.9rem;
  border: 1px solid var(--line-default);
  border-radius: 8px;
  font-size: 0.85rem;
}
.lesson-nav-link:hover { border-color: var(--line-strong); background: var(--hover-wash); }
.lesson-nav-link.next { text-align: right; margin-left: auto; flex-direction: row-reverse; }
.lesson-nav-text { display: flex; flex-direction: column; gap: 0.15rem; min-width: 0; }
.lesson-nav-text > span:last-child {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-weight: 600;
}
.lesson-nav-label { font-size: 0.72rem; color: var(--fg-faint); text-transform: uppercase; letter-spacing: 0.04em; }
</style>
