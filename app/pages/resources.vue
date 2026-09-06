<script setup lang="ts">
// A short, hand-picked starting list — not a submission, just where I
// actually learn from. Real, well-known public resources, not filler.
const CURATED = [
  { title: 'Trailhead', description: "Salesforce's own free, hands-on learning platform — where most people start.", url: 'https://trailhead.salesforce.com', icon: 'lucide:mountain' },
  { title: 'Apex Developer Guide', description: 'The official reference for the language this whole build is written in.', url: 'https://developer.salesforce.com/docs/atlas.en-us.apexcode.meta/apexcode/', icon: 'lucide:book-marked' },
  { title: 'Salesforce Well-Architected', description: "Salesforce's own design guidance — the closest thing to a style guide for decisions like the ones in these lessons.", url: 'https://architect.salesforce.com/well-architected/', icon: 'lucide:layout-template' },
  { title: 'Salesforce Stack Exchange', description: 'The best place to ask a specific, answerable Salesforce question and get a real answer.', url: 'https://salesforce.stackexchange.com', icon: 'lucide:message-circle-question' }
]

const { user } = useAuth()

const { data, refresh } = await useAsyncData('resources', () =>
  $fetch<{ resources: any[] }>('/api/resources')
)

const title = ref('')
const description = ref('')
const url = ref('')
const file = ref<File | null>(null)
const error = ref('')
const success = ref(false)
const pending = ref(false)

function onFileChange(e: Event) {
  file.value = (e.target as HTMLInputElement).files?.[0] ?? null
}

async function onSubmit() {
  error.value = ''
  success.value = false
  pending.value = true
  try {
    if (file.value) {
      const form = new FormData()
      form.append('title', title.value)
      form.append('description', description.value)
      if (url.value) form.append('url', url.value)
      form.append('file', file.value)
      await $fetch('/api/resources', { method: 'POST', body: form })
    } else {
      await $fetch('/api/resources', {
        method: 'POST',
        body: { title: title.value, description: description.value, url: url.value }
      })
    }
    title.value = ''
    description.value = ''
    url.value = ''
    file.value = null
    success.value = true
  } catch (e: any) {
    error.value = e?.data?.statusMessage ?? 'Could not submit.'
  } finally {
    pending.value = false
  }
}
</script>

<template>
  <div class="container resources">
    <h1><Icon name="lucide:library" class="title-icon" />Community resources</h1>
    <p>Blog posts, videos, tools, cheat sheets — anything that helped you learn this org's patterns.</p>

    <SectionDivider label="Where I actually learn from" />
    <div class="resource-grid curated-grid">
      <a v-for="r in CURATED" :key="r.title" class="resource-card curated-card" :href="r.url" target="_blank" rel="noopener">
        <div class="curated-icon"><Icon :name="r.icon" /></div>
        <h3>{{ r.title }}</h3>
        <p>{{ r.description }}</p>
      </a>
    </div>

    <SectionDivider label="Submitted by the community" />
    <div class="resource-grid">
      <a
        v-for="r in data?.resources"
        :key="r.id"
        class="resource-card"
        :href="r.url ?? r.fileUrl"
        target="_blank"
        rel="noopener"
      >
        <h3>{{ r.title }}</h3>
        <p>{{ r.description }}</p>
        <span class="submitted-by">via {{ r.submittedBy }}</span>
      </a>
    </div>

    <section v-if="user" class="submit-section">
      <h2>Submit a resource</h2>
      <p class="hint">New submissions are reviewed before they appear publicly.</p>
      <form class="resource-form" @submit.prevent="onSubmit">
        <label>Title <input v-model="title" type="text" required maxlength="150"></label>
        <label>Description <textarea v-model="description" required maxlength="1000" rows="3" /></label>
        <label>Link (optional if attaching a file) <input v-model="url" type="url"></label>
        <label>Attachment (optional) <input type="file" @change="onFileChange"></label>
        <p v-if="error" class="form-error">{{ error }}</p>
        <p v-if="success" class="form-success">Submitted — thanks! It'll appear once reviewed.</p>
        <button type="submit" :disabled="pending">{{ pending ? 'Submitting…' : 'Submit' }}</button>
      </form>
    </section>
    <p v-else><NuxtLink to="/login">Sign in</NuxtLink> to submit a resource.</p>
  </div>
</template>

<style scoped>
.resources { padding-block: 3rem; }
h1 { display: flex; align-items: center; gap: 0.6rem; }
.title-icon { color: var(--fg-accent); }
.resource-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(16rem, 1fr)); gap: 1rem; margin-block: 1.5rem; }
.resource-card {
  display: block; padding: 1rem; border: 1px solid var(--line-default); border-radius: 10px;
  background: var(--bg-surface); text-decoration: none; color: inherit;
}
.resource-card:hover { border-color: var(--accent); background: var(--hover-wash); }
.resource-card h3 { margin: 0 0 0.4rem; color: var(--fg-default); }
.resource-card p { margin: 0 0 0.6rem; color: var(--fg-muted); font-size: 0.9rem; }
.submitted-by { color: var(--fg-faint); font-size: 0.8rem; }
.curated-grid { margin-top: 1rem; }
.curated-icon {
  width: 2.25rem; height: 2.25rem; display: flex; align-items: center; justify-content: center;
  border-radius: 8px; background: var(--accent-soft); color: var(--accent-soft-fg); font-size: 1.1rem;
  margin-bottom: 0.6rem;
}
.submit-section { margin-top: 2.5rem; padding-top: 2rem; border-top: 1px solid var(--line-subtle); max-width: 32rem; }
.hint { color: var(--fg-faint); font-size: 0.85rem; }
.resource-form { display: grid; gap: 1rem; }
label { display: grid; gap: 0.375rem; color: var(--fg-muted); font-size: 0.9rem; }
input, textarea {
  padding: 0.6rem 0.75rem; border: 1px solid var(--line-default); border-radius: 6px;
  background: var(--bg-canvas); color: var(--fg-default); font: inherit;
}
button {
  padding: 0.65rem 1rem; border: none; border-radius: 6px; background: var(--accent);
  color: var(--fg-on-accent); font-weight: 600; cursor: pointer; justify-self: start;
}
button:hover:not(:disabled) { background: var(--accent-hover); }
button:disabled { opacity: 0.6; cursor: not-allowed; }
.form-error { color: var(--danger-fg); background: var(--danger-bg); border: 1px solid var(--danger-line); border-radius: 6px; padding: 0.5rem 0.75rem; font-size: 0.9rem; }
.form-success { color: var(--success-fg); background: var(--success-bg); border: 1px solid var(--success-line); border-radius: 6px; padding: 0.5rem 0.75rem; font-size: 0.9rem; }
</style>
