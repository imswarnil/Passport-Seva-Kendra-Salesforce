<script setup lang="ts">
defineProps<{ label?: string }>()
</script>

<template>
  <div class="divider" role="separator">
    <span class="divider-line" />
    <span v-if="label" class="divider-label">{{ label }}</span>
    <span class="divider-line" />
  </div>
</template>

<style scoped>
.divider {
  display: flex;
  align-items: center;
  gap: 1rem;
  margin: 3rem 0;
}
.divider-line {
  flex: 1;
  height: 1px;
  background: var(--line-default);
}
.divider-label {
  font-size: 0.75rem;
  letter-spacing: 0.08em;
  text-transform: uppercase;
  color: var(--fg-faint);
  white-space: nowrap;
}
</style>
