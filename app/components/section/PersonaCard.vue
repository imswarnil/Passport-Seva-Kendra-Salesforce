<script setup lang="ts">
defineProps<{
  icon: string
  name: string
  role: string
  app: string
  owns: string
}>()
</script>

<template>
  <div class="persona-card">
    <div class="persona-icon"><Icon :name="icon" /></div>
    <div class="persona-body">
      <p class="persona-role">{{ role }}</p>
      <p class="persona-name">{{ name }}</p>
      <p class="persona-meta"><Icon name="lucide:layout-grid" />{{ app }}</p>
      <p class="persona-meta"><Icon name="lucide:folder" />{{ owns }}</p>
    </div>
  </div>
</template>

<style scoped>
.persona-card {
  display: flex;
  gap: 0.9rem;
  padding: 1.1rem;
  background: var(--bg-surface);
  border: 1px solid var(--line-default);
  border-radius: 10px;
}
.persona-icon {
  flex: none;
  width: 2.5rem;
  height: 2.5rem;
  display: flex;
  align-items: center;
  justify-content: center;
  border-radius: 8px;
  background: var(--accent-soft);
  color: var(--accent-soft-fg);
  font-size: 1.2rem;
}
.persona-body { min-width: 0; }
.persona-role {
  margin: 0 0 0.15em;
  font-size: 0.72rem;
  text-transform: uppercase;
  letter-spacing: 0.04em;
  color: var(--fg-faint);
}
.persona-name { margin: 0 0 0.4em; font-weight: 700; color: var(--fg-default); }
.persona-meta {
  display: flex;
  align-items: center;
  gap: 0.35rem;
  margin: 0.1em 0;
  font-size: 0.82rem;
  color: var(--fg-subtle);
}
</style>
