<script setup lang="ts">
const { user, loaded, refresh, updateProfile } = useAuth()
const { completedSlugs } = useProgress()
const router = useRouter()

if (import.meta.client && !loaded.value) await refresh()
if (import.meta.client && loaded.value && !user.value) router.push('/login')

const { data: rawLessons } = await useAsyncData('dashboard-lessons', () =>
  queryCollection('lessons').select('path', 'title', 'minutes', 'description').all()
)
// Excludes each module's `.navigation.yml` row (see content.config.ts) — it
// shares this collection but is never a real lesson and never sets a
// description.
const lessons = computed(() => (rawLessons.value ?? []).filter(l => l.description))

const { data: mySubmissions, pending: submissionsPending } = await useAsyncData(
  'my-resource-submissions',
  () => user.value ? $fetch<{ resources: any[] }>('/api/resources/mine') : Promise.resolve({ resources: [] }),
  { watch: [user] }
)

function lessonSlug(path: string) {
  return path.replace(/^\//, '')
}

const total = computed(() => lessons.value.length)
const done = computed(() => completedSlugs.value.length)

// Profile editing
const editingProfile = ref(false)
const displayName = ref(user.value?.displayName ?? '')
const profileError = ref('')
const profilePending = ref(false)
const profileSaved = ref(false)

watch(user, (u) => { if (u) displayName.value = u.displayName })

async function saveProfile() {
  profileError.value = ''
  profilePending.value = true
  try {
    await updateProfile({ displayName: displayName.value })
    editingProfile.value = false
    profileSaved.value = true
    setTimeout(() => { profileSaved.value = false }, 2500)
  } catch (e: any) {
    profileError.value = e?.data?.statusMessage ?? 'Could not save.'
  } finally {
    profilePending.value = false
  }
}
</script>

<template>
  <div v-if="user" class="container dashboard">
    <section class="profile-header">
      <div>
        <h1>Welcome back, {{ user.displayName }}</h1>
        <p class="profile-email">{{ user.email }}</p>
      </div>
      <button v-if="!editingProfile" type="button" class="btn btn-ghost" @click="editingProfile = true">
        <Icon name="lucide:pencil" /> Edit profile
      </button>
    </section>

    <form v-if="editingProfile" class="profile-form" @submit.prevent="saveProfile">
      <label>
        Display name
        <input v-model="displayName" type="text" required maxlength="80">
      </label>
      <p v-if="profileError" class="form-error">{{ profileError }}</p>
      <div class="profile-form-actions">
        <button type="submit" class="btn btn-primary" :disabled="profilePending">{{ profilePending ? 'Saving…' : 'Save' }}</button>
        <button type="button" class="btn btn-ghost" @click="editingProfile = false">Cancel</button>
      </div>
    </form>
    <p v-if="profileSaved" class="form-success"><Icon name="lucide:check" /> Profile updated.</p>

    <section class="progress-summary">
      <p>{{ done }} of {{ total }} lessons complete</p>
      <div class="progress-bar"><div class="progress-fill" :style="{ width: `${total ? (done / total) * 100 : 0}%` }" /></div>
    </section>

    <section>
      <h2>Lessons</h2>
      <ul class="lesson-list">
        <li v-for="lesson in lessons" :key="lesson.path">
          <NuxtLink :to="lesson.path">{{ lesson.title }}</NuxtLink>
          <div class="lesson-list-right">
            <span v-if="completedSlugs.includes(lessonSlug(lesson.path))" class="badge badge-done">done</span>
            <ShareButton :title="lesson.title" :path="lesson.path" />
          </div>
        </li>
      </ul>
    </section>

    <section>
      <h2>Your resource submissions</h2>
      <p v-if="submissionsPending">Loading…</p>
      <p v-else-if="!mySubmissions?.resources.length">You haven't submitted any resources yet. <NuxtLink to="/resources">Submit one</NuxtLink>.</p>
      <ul v-else class="submission-list">
        <li v-for="r in mySubmissions.resources" :key="r.id">
          <strong>{{ r.title }}</strong>
          <span class="badge" :class="`badge-${r.status}`">{{ r.status }}</span>
        </li>
      </ul>
    </section>
  </div>
</template>

<style scoped>
.dashboard { padding-block: 3rem; display: grid; gap: 2.5rem; }
.profile-header { display: flex; align-items: flex-start; justify-content: space-between; gap: 1rem; }
.profile-email { margin: 0.25rem 0 0; color: var(--fg-faint); font-size: 0.9rem; }
.profile-form { display: grid; gap: 0.75rem; max-width: 24rem; margin-top: -1.5rem; }
.profile-form label { display: grid; gap: 0.375rem; color: var(--fg-muted); font-size: 0.9rem; }
.profile-form input {
  padding: 0.6rem 0.75rem; border: 1px solid var(--line-default); border-radius: 6px;
  background: var(--bg-surface); color: var(--fg-default); font: inherit;
}
.profile-form-actions { display: flex; gap: 0.6rem; }
.form-error { color: var(--danger-fg); background: var(--danger-bg); border: 1px solid var(--danger-line); border-radius: 6px; padding: 0.5rem 0.75rem; font-size: 0.9rem; }
.form-success { display: flex; align-items: center; gap: 0.4rem; color: var(--success-fg); font-size: 0.9rem; margin: -1.5rem 0 0; }

.progress-bar { height: 8px; border-radius: 999px; background: var(--bg-muted); overflow: hidden; margin-top: 0.5rem; }
.progress-fill { height: 100%; background: var(--accent); }
.lesson-list, .submission-list { list-style: none; padding: 0; display: grid; gap: 0.5rem; }
.lesson-list li, .submission-list li {
  display: flex; align-items: center; justify-content: space-between;
  padding: 0.6rem 0.9rem; border: 1px solid var(--line-subtle); border-radius: 8px; background: var(--bg-surface);
}
.lesson-list-right { display: flex; align-items: center; gap: 0.6rem; }
.badge { font-size: 0.75rem; padding: 0.15rem 0.5rem; border-radius: 999px; font-weight: 600; }
.badge-done { background: var(--success-bg); color: var(--success-fg); }
.badge-pending { background: var(--warning-bg); color: var(--warning-fg); }
.badge-approved { background: var(--success-bg); color: var(--success-fg); }
.badge-rejected { background: var(--danger-bg); color: var(--danger-fg); }
</style>
