<script setup lang="ts">
const props = defineProps<{
  title: string
  to: string
  minutes: number
  kind: 'lesson' | 'reference' | 'project'
  completed?: boolean // undefined when not signed in / not yet known
}>()

const KIND_ICON: Record<typeof props.kind, string> = {
  lesson: 'lucide:book-open',
  reference: 'lucide:bookmark',
  project: 'lucide:hammer'
}
</script>

<template>
  <NuxtLink :to="to" class="lesson-row">
    <span class="lesson-check" :class="{ done: completed }">
      <svg v-if="completed" viewBox="0 0 16 16" width="12" height="12" fill="none">
        <path d="M3 8.5 6.5 12 13 4.5" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" />
      </svg>
    </span>
    <span class="lesson-title">{{ title }}</span>
    <span class="lesson-kind" :class="kind"><Icon :name="KIND_ICON[kind]" />{{ kind }}</span>
    <span class="lesson-minutes"><Icon name="lucide:clock" />{{ minutes }} min</span>
  </NuxtLink>
</template>

<style scoped>
.lesson-row {
  display: flex;
  align-items: center;
  gap: 0.75rem;
  padding: 0.75rem 1rem;
  border-radius: 8px;
  text-decoration: none;
  color: var(--fg-default);
}
.lesson-row:hover { background: var(--hover-wash); }
.lesson-check {
  flex: none;
  width: 1.1rem;
  height: 1.1rem;
  border-radius: 50%;
  border: 1.5px solid var(--line-strong);
  display: grid;
  place-items: center;
  color: var(--fg-on-accent);
}
.lesson-check.done {
  background: var(--success-solid);
  border-color: var(--success-solid);
}
.lesson-title { flex: 1; font-size: 0.92rem; }
.lesson-kind {
  display: inline-flex;
  align-items: center;
  gap: 0.3rem;
  font-size: 0.7rem;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  padding: 0.15em 0.55em;
  border-radius: 999px;
  background: var(--bg-muted);
  color: var(--fg-subtle);
}
.lesson-kind.project { background: var(--accent-soft); color: var(--accent-soft-fg); }
.lesson-minutes {
  display: inline-flex;
  align-items: center;
  gap: 0.3rem;
  font-size: 0.78rem;
  color: var(--fg-faint);
  white-space: nowrap;
}
</style>
