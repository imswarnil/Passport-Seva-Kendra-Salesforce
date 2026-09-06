<script setup lang="ts">
// Steps prefixed with "⚙" render as automatic (platform-driven) steps instead
// of a user action — matches the ⚙︎ convention used throughout the lessons.
defineProps<{ title?: string; steps: string[] }>()
</script>

<template>
  <div class="flow">
    <p v-if="title" class="flow-title">{{ title }}</p>
    <ol class="flow-steps">
      <li v-for="(step, i) in steps" :key="i" :class="{ auto: step.startsWith('⚙') }">
        <span class="flow-index">{{ i + 1 }}</span>
        <span class="flow-text">{{ step.replace(/^⚙\s*/, '') }}</span>
      </li>
    </ol>
  </div>
</template>

<style scoped>
.flow { margin: 1.5rem 0; }
.flow-title { font-weight: 600; margin-bottom: 0.75rem; color: var(--fg-default); }
.flow-steps { list-style: none; margin: 0; padding: 0; display: flex; flex-direction: column; gap: 0.5rem; }
.flow-steps li {
  display: flex;
  align-items: baseline;
  gap: 0.75rem;
  padding: 0.6rem 0.9rem;
  background: var(--bg-surface);
  border: 1px solid var(--line-subtle);
  border-radius: 6px;
}
.flow-steps li.auto {
  border-style: dashed;
  background: var(--bg-muted);
}
.flow-index {
  flex: none;
  width: 1.5rem;
  height: 1.5rem;
  display: grid;
  place-items: center;
  border-radius: 50%;
  background: var(--accent-soft);
  color: var(--accent-soft-fg);
  font-size: 0.75rem;
  font-weight: 700;
}
.flow-text { color: var(--fg-muted); }
</style>
