<script setup lang="ts">
const { data: lessons } = await useAsyncData('lessons-index', () => queryCollection('lessons').all())

// Excludes each module's `.navigation.yml` row — it lives in this same
// collection (content.config.ts) but is never a real lesson, and never sets
// `description`, which is what distinguishes it from one.
const realLessons = computed(() => (lessons.value ?? []).filter(l => l.description))

const grouped = computed(() =>
  LESSON_MODULES.map(m => ({
    ...m,
    items: realLessons.value
      .filter(l => l.path.startsWith(`/${m.slug}/`))
      .sort((a, b) => a.path.localeCompare(b.path))
  })).filter(m => m.items.length)
)
</script>

<template>
  <LessonsShell>
    <Hero title="Lessons" description="Six modules, in the order the org was actually built — each one points at the real metadata it's describing." />

    <div v-for="mod in grouped" :key="mod.slug" class="module-block">
      <SectionDivider :label="mod.title" />
      <div class="lesson-list">
        <LessonRow
          v-for="item in mod.items"
          :key="item.path"
          :title="item.title"
          :to="item.path"
          :minutes="item.minutes!"
          :kind="item.kind"
        />
      </div>
    </div>
  </LessonsShell>
</template>

<style scoped>
.module-block { margin-bottom: 1rem; }
.lesson-list { display: flex; flex-direction: column; gap: 0.25rem; margin-bottom: 2rem; }
</style>
