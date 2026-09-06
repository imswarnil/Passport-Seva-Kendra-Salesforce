<script setup lang="ts">
defineProps<{
  label: string
  api: string
  relationship: string
  purpose: string
}>()
</script>

<template>
  <div class="object-preview-card">
    <div class="object-preview-icon"><Icon name="lucide:database" /></div>
    <div class="object-preview-body">
      <p class="object-preview-label">{{ label }}</p>
      <code class="object-preview-api">{{ api }}</code>
      <span class="object-preview-rel">{{ relationship }}</span>
      <p class="object-preview-purpose">{{ purpose }}</p>
    </div>
  </div>
</template>

<style scoped>
.object-preview-card {
  display: flex;
  gap: 0.85rem;
  padding: 1.1rem;
  background: var(--bg-surface);
  border: 1px solid var(--line-default);
  border-radius: 10px;
}
.object-preview-icon {
  flex: none;
  width: 2.25rem;
  height: 2.25rem;
  display: flex;
  align-items: center;
  justify-content: center;
  border-radius: 8px;
  background: var(--info-bg);
  color: var(--info-fg);
  font-size: 1.05rem;
}
.object-preview-body { min-width: 0; }
.object-preview-label { margin: 0 0 0.25em; font-weight: 700; color: var(--fg-default); }
.object-preview-api {
  display: inline-block;
  background: var(--bg-muted);
  border-radius: 4px;
  padding: 0.05em 0.4em;
  font-size: 0.78rem;
  color: var(--fg-subtle);
  margin-right: 0.4rem;
}
.object-preview-rel {
  font-size: 0.72rem;
  text-transform: uppercase;
  letter-spacing: 0.03em;
  color: var(--fg-faint);
}
.object-preview-purpose { margin: 0.5em 0 0; font-size: 0.86rem; color: var(--fg-muted); }
</style>
