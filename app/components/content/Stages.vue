<script setup lang="ts">
const props = defineProps<{
  title?: string
  stages: string[]
  terminal?: string[]
  current?: string
}>()
</script>

<template>
  <div class="stages">
    <p v-if="title" class="stages-title">{{ title }}</p>
    <div class="stages-track">
      <span
        v-for="stage in stages"
        :key="stage"
        class="stage-pill"
        :class="{ current: stage === props.current }"
      >{{ stage }}</span>
      <span
        v-for="stage in terminal ?? []"
        :key="stage"
        class="stage-pill terminal"
        :class="{ current: stage === props.current }"
      >{{ stage }}</span>
    </div>
  </div>
</template>

<style scoped>
.stages { margin: 1.5rem 0; }
.stages-title {
  font-family: ui-monospace, monospace;
  font-size: 0.85rem;
  color: var(--fg-subtle);
  margin-bottom: 0.6rem;
}
.stages-track { display: flex; flex-wrap: wrap; gap: 0.4rem; }
.stage-pill {
  font-size: 0.8rem;
  padding: 0.3em 0.7em;
  border-radius: 999px;
  background: var(--bg-muted);
  color: var(--fg-muted);
  border: 1px solid var(--line-default);
}
.stage-pill.terminal {
  background: var(--danger-bg);
  color: var(--danger-fg);
  border-color: var(--danger-line);
}
.stage-pill.current {
  background: var(--accent);
  color: var(--fg-on-accent);
  border-color: transparent;
  font-weight: 600;
}
</style>
