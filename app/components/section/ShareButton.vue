<script setup lang="ts">
const props = defineProps<{ title: string, text?: string, path?: string }>()
const copied = ref(false)

async function share() {
  const url = props.path ? `${window.location.origin}${props.path}` : window.location.href
  if (navigator.share) {
    try {
      await navigator.share({ title: props.title, text: props.text, url })
      return
    } catch {
      // User cancelled the native share sheet — fall through to nothing,
      // not the clipboard fallback below (that would be a surprise after
      // an intentional cancel).
      return
    }
  }
  await navigator.clipboard.writeText(url)
  copied.value = true
  setTimeout(() => { copied.value = false }, 2000)
}
</script>

<template>
  <button type="button" class="share-btn" @click="share">
    <Icon :name="copied ? 'lucide:check' : 'lucide:share-2'" />
    {{ copied ? 'Link copied' : 'Share' }}
  </button>
</template>

<style scoped>
.share-btn {
  display: inline-flex;
  align-items: center;
  gap: 0.4rem;
  padding: 0.4rem 0.8rem;
  border: 1px solid var(--line-default);
  border-radius: 6px;
  background: var(--bg-surface);
  color: var(--fg-muted);
  font-size: 0.85rem;
  cursor: pointer;
}
.share-btn:hover { background: var(--hover-wash); color: var(--fg-default); }
</style>
