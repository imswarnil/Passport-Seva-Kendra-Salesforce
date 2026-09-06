<script setup lang="ts">
// Mount as <CommentThread :lesson-slug="..." /> — lessonSlug matches the
// Nuxt Content path with the leading "lessons/" segment stripped, e.g.
// "data-model/data-modeling".
const props = defineProps<{ lessonSlug: string }>()

const { user } = useAuth()

const { data, refresh } = await useAsyncData(
  () => `comments-${props.lessonSlug}`,
  () => $fetch<{ comments: any[] }>(`/api/comments/${props.lessonSlug}`)
)

const body = ref('')
const error = ref('')
const pending = ref(false)

async function onSubmit() {
  error.value = ''
  pending.value = true
  try {
    await $fetch(`/api/comments/${props.lessonSlug}`, { method: 'POST', body: { body: body.value } })
    body.value = ''
    await refresh()
  } catch (e: any) {
    error.value = e?.data?.statusMessage ?? 'Could not post comment.'
  } finally {
    pending.value = false
  }
}
</script>

<template>
  <div class="comment-thread">
    <h2>Comments</h2>

    <ul v-if="data?.comments.length" class="comment-list">
      <li v-for="c in data.comments" :key="c.id">
        <p class="comment-body">{{ c.body }}</p>
        <p class="comment-meta">{{ c.displayName }}</p>
      </li>
    </ul>
    <p v-else class="empty">No comments yet — be the first.</p>

    <form v-if="user" class="comment-form" @submit.prevent="onSubmit">
      <textarea v-model="body" required maxlength="2000" rows="3" placeholder="Ask a question or share a tip…" />
      <p v-if="error" class="form-error">{{ error }}</p>
      <button type="submit" :disabled="pending">{{ pending ? 'Posting…' : 'Post comment' }}</button>
    </form>
    <p v-else class="empty"><NuxtLink to="/login">Sign in</NuxtLink> to comment.</p>
  </div>
</template>

<style scoped>
.comment-thread { margin-top: 3rem; padding-top: 2rem; border-top: 1px solid var(--line-subtle); }
.comment-list { list-style: none; padding: 0; display: grid; gap: 0.75rem; margin-bottom: 1.5rem; }
.comment-list li { padding: 0.9rem; border: 1px solid var(--line-subtle); border-radius: 8px; background: var(--bg-surface); }
.comment-body { margin: 0 0 0.35rem; color: var(--fg-default); }
.comment-meta { margin: 0; color: var(--fg-faint); font-size: 0.85rem; }
.empty { color: var(--fg-faint); }
.comment-form { display: grid; gap: 0.75rem; max-width: 32rem; }
textarea {
  padding: 0.6rem 0.75rem; border: 1px solid var(--line-default); border-radius: 6px;
  background: var(--bg-canvas); color: var(--fg-default); font: inherit;
}
button {
  padding: 0.55rem 1rem; border: none; border-radius: 6px; background: var(--accent);
  color: var(--fg-on-accent); font-weight: 600; cursor: pointer; justify-self: start;
}
button:hover:not(:disabled) { background: var(--accent-hover); }
button:disabled { opacity: 0.6; cursor: not-allowed; }
.form-error { color: var(--danger-fg); background: var(--danger-bg); border: 1px solid var(--danger-line); border-radius: 6px; padding: 0.5rem 0.75rem; font-size: 0.9rem; }
</style>
