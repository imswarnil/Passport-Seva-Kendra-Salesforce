<script setup lang="ts">
defineProps<{
  icon?: string
  title: string
  description: string
  to: string
  lessonCount: number
  progress?: number // 0-100; hidden when undefined (no session yet, or not signed in)
}>()
</script>

<template>
  <NuxtLink :to="to" class="module-card">
    <div v-if="icon" class="module-icon"><Icon :name="icon" /></div>
    <p class="module-title">{{ title }}</p>
    <p class="module-description">{{ description }}</p>
    <div class="module-footer">
      <span class="module-count">{{ lessonCount }} lesson{{ lessonCount === 1 ? '' : 's' }}</span>
      <div v-if="progress !== undefined" class="module-progress" :aria-label="`${progress}% complete`">
        <div class="module-progress-fill" :style="{ width: `${progress}%` }" />
      </div>
    </div>
  </NuxtLink>
</template>

<style scoped>
.module-card {
  display: block;
  padding: 1.25rem 1.5rem;
  background: var(--bg-surface);
  border: 1px solid var(--line-default);
  border-radius: 10px;
  text-decoration: none;
  transition: border-color 0.15s ease, background 0.15s ease;
}
.module-card:hover {
  border-color: var(--line-strong);
  background: var(--hover-wash);
}
.module-icon {
  width: 2.25rem;
  height: 2.25rem;
  display: flex;
  align-items: center;
  justify-content: center;
  border-radius: 8px;
  background: var(--accent-soft);
  color: var(--accent-soft-fg);
  font-size: 1.15rem;
  margin-bottom: 0.75rem;
}
.module-title {
  margin: 0 0 0.35em;
  font-weight: 600;
  font-size: 1.05rem;
  color: var(--fg-default);
}
.module-description {
  margin: 0 0 1rem;
  font-size: 0.9rem;
  color: var(--fg-muted);
}
.module-footer {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 1rem;
}
.module-count {
  font-size: 0.78rem;
  color: var(--fg-faint);
  white-space: nowrap;
}
.module-progress {
  flex: 1;
  height: 4px;
  border-radius: 999px;
  background: var(--bg-muted);
  overflow: hidden;
}
.module-progress-fill {
  height: 100%;
  background: var(--accent);
}
</style>
