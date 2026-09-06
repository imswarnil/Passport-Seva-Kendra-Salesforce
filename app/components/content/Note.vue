<script setup lang="ts">
defineProps<{ title?: string }>()
</script>

<template>
  <aside class="note">
    <Icon name="lucide:info" class="note-icon" />
    <div class="note-content">
      <p v-if="title" class="note-title">{{ title }}</p>
      <div class="note-body">
        <MDCSlot :use="$slots.default" unwrap="p" />
      </div>
    </div>
  </aside>
</template>

<style scoped>
.note {
  display: flex;
  gap: 0.75rem;
  background: var(--info-bg);
  border: 1px solid var(--info-line);
  border-radius: 8px;
  padding: 1rem 1.25rem;
  margin: 1.5rem 0;
}
.note-icon { flex: none; color: var(--info-fg); font-size: 1.15rem; margin-top: 0.15em; }
.note-content { min-width: 0; }
.note-title {
  margin: 0 0 0.35em;
  font-weight: 600;
  color: var(--info-fg);
}
.note-body :deep(p) {
  margin: 0;
  color: var(--info-fg);
}
</style>
