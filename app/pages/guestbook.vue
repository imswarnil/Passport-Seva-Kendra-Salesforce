<script setup lang="ts">
const { user } = useAuth()
const route = useRoute()
const router = useRouter()

interface Entry {
  id: string
  displayName: string
  message: string
  hasImage: boolean
  imageId: string | null
  createdAt: string
}
interface GuestbookResult { entries: Entry[], page: number, hasMore: boolean, hasPrev: boolean }

const page = computed(() => Math.max(1, Number.parseInt(String(route.query.page ?? '1'), 10) || 1))
const { data, refresh, pending: listPending } = await useAsyncData<GuestbookResult>(
  'guestbook',
  () => $fetch('/api/guestbook', { query: { page: page.value } }),
  { watch: [page] }
)
function goToPage(p: number) {
  router.push({ query: { ...route.query, page: p > 1 ? p : undefined } })
}

const displayName = ref('')
const message = ref('')
const error = ref('')
const pending = ref(false)
const showDoodle = ref(false)
const pendingDoodle = ref<string | null>(null) // dataURL, shown as a preview before submit

function insertEmoji(emoji: string) {
  message.value += emoji
}

async function onSaveDoodle(dataUrl: string) {
  pendingDoodle.value = dataUrl
  showDoodle.value = false
}

async function onSubmit() {
  error.value = ''
  pending.value = true
  try {
    let imageKey: string | undefined
    if (pendingDoodle.value) {
      const { imageKey: key } = await $fetch<{ imageKey: string }>('/api/guestbook/drawing', {
        method: 'POST',
        body: { dataUrl: pendingDoodle.value }
      })
      imageKey = key
    }
    await $fetch('/api/guestbook', {
      method: 'POST',
      body: { displayName: user.value ? undefined : displayName.value, message: message.value, imageKey }
    })
    message.value = ''
    pendingDoodle.value = null
    await refresh()
  } catch (e: any) {
    error.value = e?.data?.statusMessage ?? 'Could not post.'
  } finally {
    pending.value = false
  }
}
</script>

<template>
  <div class="container guestbook">
    <h1><Icon name="lucide:message-square-heart" class="title-icon" />Guestbook</h1>
    <p>Learning something, teaching a class with this, found a bug — leave a note. Sign in to add a doodle.</p>

    <form class="guestbook-form" @submit.prevent="onSubmit">
      <label v-if="!user">
        Name
        <input v-model="displayName" type="text" required maxlength="80">
      </label>
      <label>
        Message
        <textarea v-model="message" required maxlength="1000" rows="3" />
      </label>

      <div class="form-toolbar">
        <EmojiPicker @pick="insertEmoji" />
        <button v-if="user && !showDoodle && !pendingDoodle" type="button" class="btn btn-ghost" @click="showDoodle = true">
          <Icon name="lucide:pencil" /> Add a doodle
        </button>
      </div>

      <DoodlePad v-if="showDoodle" @save="onSaveDoodle" @cancel="showDoodle = false" />
      <div v-if="pendingDoodle" class="doodle-preview">
        <img :src="pendingDoodle" alt="Your doodle" width="120">
        <button type="button" class="btn btn-ghost" @click="pendingDoodle = null"><Icon name="lucide:x" /> Remove</button>
      </div>

      <p v-if="error" class="form-error">{{ error }}</p>
      <button type="submit" class="btn btn-primary submit-btn" :disabled="pending">
        {{ pending ? 'Posting…' : 'Sign the guestbook' }}
      </button>
    </form>

    <div v-if="listPending" class="state-block"><Icon name="lucide:loader-circle" class="spin" /> Loading…</div>
    <ul v-else class="entries">
      <li v-for="entry in data?.entries" :key="entry.id">
        <img v-if="entry.hasImage" :src="`/api/guestbook/image/${entry.imageId}`" alt="A doodle" class="entry-doodle">
        <p class="entry-message">{{ entry.message }}</p>
        <p class="entry-meta">— {{ entry.displayName }}</p>
      </li>
    </ul>

    <nav v-if="data && (data.hasPrev || data.hasMore)" class="pagination">
      <button type="button" class="btn btn-ghost" :disabled="!data.hasPrev" @click="goToPage(page - 1)">
        <Icon name="lucide:arrow-left" /> Newer
      </button>
      <span class="pagination-page">Page {{ page }}</span>
      <button type="button" class="btn btn-ghost" :disabled="!data.hasMore" @click="goToPage(page + 1)">
        Older <Icon name="lucide:arrow-right" />
      </button>
    </nav>
  </div>
</template>

<style scoped>
.guestbook { padding-block: 3rem; max-width: 40rem; }
h1 { display: flex; align-items: center; gap: 0.6rem; }
.title-icon { color: var(--fg-accent); }
.guestbook-form { display: grid; gap: 1rem; margin-block: 1.5rem; }
label { display: grid; gap: 0.375rem; color: var(--fg-muted); font-size: 0.9rem; }
input, textarea {
  padding: 0.6rem 0.75rem; border: 1px solid var(--line-default); border-radius: 6px;
  background: var(--bg-surface); color: var(--fg-default); font: inherit;
}
.form-toolbar { display: flex; align-items: center; gap: 0.6rem; }
.doodle-preview { display: flex; align-items: center; gap: 0.75rem; }
.doodle-preview img { border: 1px solid var(--line-default); border-radius: 6px; }
.submit-btn { justify-self: start; }
.form-error { color: var(--danger-fg); background: var(--danger-bg); border: 1px solid var(--danger-line); border-radius: 6px; padding: 0.5rem 0.75rem; font-size: 0.9rem; }

.state-block { display: flex; align-items: center; gap: 0.5rem; color: var(--fg-muted); padding: 1.5rem 0; }
.spin { animation: spin 1s linear infinite; }
@keyframes spin { to { transform: rotate(360deg); } }

.entries { list-style: none; padding: 0; display: grid; gap: 0.75rem; margin-bottom: 1.5rem; }
.entries li { padding: 0.9rem; border: 1px solid var(--line-subtle); border-radius: 8px; background: var(--bg-surface); }
.entry-doodle { border-radius: 6px; border: 1px solid var(--line-subtle); margin-bottom: 0.5rem; }
.entry-message { margin: 0 0 0.35rem; color: var(--fg-default); }
.entry-meta { margin: 0; color: var(--fg-faint); font-size: 0.85rem; }

.pagination { display: flex; align-items: center; justify-content: center; gap: 1.25rem; margin-top: 1.5rem; }
.pagination-page { font-size: 0.85rem; color: var(--fg-subtle); }
.pagination .btn:disabled { opacity: 0.4; cursor: not-allowed; }
</style>
