<script setup lang="ts">
defineProps<{ title?: string }>()
</script>

<template>
  <aside class="warning">
    <Icon name="lucide:triangle-alert" class="warning-icon" />
    <div class="warning-content">
      <p v-if="title" class="warning-title">{{ title }}</p>
      <div class="warning-body">
        <MDCSlot :use="$slots.default" unwrap="p" />
      </div>
    </div>
  </aside>
</template>

<style scoped>
.warning {
  display: flex;
  gap: 0.75rem;
  background: var(--warning-bg);
  border: 1px solid var(--warning-line);
  border-radius: 8px;
  padding: 1rem 1.25rem;
  margin: 1.5rem 0;
}
.warning-icon { flex: none; color: var(--warning-fg); font-size: 1.15rem; margin-top: 0.15em; }
.warning-content { min-width: 0; }
.warning-title {
  margin: 0 0 0.35em;
  font-weight: 600;
  color: var(--warning-fg);
}
.warning-body :deep(p) {
  margin: 0;
  color: var(--warning-fg);
}
</style>
