<script setup lang="ts">
defineProps<{ name: string }>()
</script>

<template>
  <code class="object-ref"><Icon name="lucide:database" />{{ name }}</code>
</template>

<style scoped>
.object-ref {
  display: inline-flex;
  align-items: center;
  gap: 0.3em;
  background: var(--accent-soft);
  color: var(--accent-soft-fg);
  border: none;
  border-radius: 4px;
  padding: 0.1em 0.5em;
  font-size: 0.85em;
  font-weight: 600;
}
</style>
