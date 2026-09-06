<script setup lang="ts">
const emit = defineEmits<{ pick: [emoji: string] }>()
const open = ref(false)

// A small curated set rather than a full picker library — this is a
// guestbook, not a chat app; picking from ~30 covers the actual use case.
const EMOJI = ['👋', '🎉', '🙌', '✅', '🚀', '💡', '🔥', '❤️', '😄', '🤔', '👏', '⭐', '📌', '🛂', '🧩', '🏗️', '📚', '🐛', '☕', '🙏']

function pick(e: string) {
  emit('pick', e)
  open.value = false
}
</script>

<template>
  <div class="emoji-picker">
    <button type="button" class="emoji-toggle" :aria-expanded="open" @click="open = !open">
      <Icon name="lucide:smile" />
    </button>
    <div v-if="open" class="emoji-panel">
      <button v-for="e in EMOJI" :key="e" type="button" class="emoji-option" @click="pick(e)">{{ e }}</button>
    </div>
  </div>
</template>

<style scoped>
.emoji-picker { position: relative; display: inline-block; }
.emoji-toggle {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 2.1rem;
  height: 2.1rem;
  border: 1px solid var(--line-default);
  border-radius: 6px;
  background: var(--bg-surface);
  color: var(--fg-muted);
  cursor: pointer;
}
.emoji-toggle:hover { background: var(--hover-wash); color: var(--fg-default); }
.emoji-panel {
  position: absolute;
  bottom: calc(100% + 0.4rem);
  left: 0;
  display: grid;
  grid-template-columns: repeat(6, 1fr);
  gap: 0.15rem;
  padding: 0.5rem;
  background: var(--bg-raised);
  border: 1px solid var(--line-default);
  border-radius: 8px;
  box-shadow: 0 8px 24px var(--bg-scrim);
  z-index: 20;
}
.emoji-option {
  border: none;
  background: none;
  font-size: 1.15rem;
  padding: 0.25rem;
  border-radius: 5px;
  cursor: pointer;
  line-height: 1;
}
.emoji-option:hover { background: var(--hover-wash); }
</style>
