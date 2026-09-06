<script setup lang="ts">
// One fetch, shared by every page that mounts this component (lessons index
// + every lesson reader) — Nuxt dedupes identical useAsyncData keys, so
// navigating between lessons doesn't refetch the whole tree.
const { data: rawNav } = await useAsyncData('lessons-nav', () =>
  queryCollectionNavigation('lessons', ['icon', 'minutes', 'kind'])
)

// queryCollectionNavigation returns ONE root node for the collection itself
// (path "/lessons", title "Lessons") whose .children are the six module
// folders — not the modules directly. Drill one level in so `nav` is the
// module list this component actually renders.
const nav = computed(() => {
  const root = rawNav.value ?? []
  if (root.length === 1 && root[0].path === '/lessons') return root[0].children ?? []
  return root
})

const route = useRoute()
const isActive = (path: string) => route.path === path
const isActiveModule = (mod: { path: string, children?: { path: string }[] }) =>
  (mod.children ?? []).some(c => isActive(c.path))

const query = ref('')
const filtered = computed(() => {
  const q = query.value.trim().toLowerCase()
  if (!q) return nav.value
  return (nav.value as any[])
    .map(mod => ({ ...mod, children: (mod.children ?? []).filter((l: any) => l.title.toLowerCase().includes(q)) }))
    .filter(mod => mod.title.toLowerCase().includes(q) || mod.children.length)
})

// Modules collapse to just the active one by default; searching expands
// every module that still has a match so results aren't hidden behind a
// closed accordion.
const expanded = ref<Set<string>>(new Set())
watchEffect(() => {
  for (const mod of nav.value ?? []) {
    if (isActiveModule(mod as any)) expanded.value.add(mod.path)
  }
})
watch(query, (q) => {
  if (q.trim()) for (const mod of filtered.value) expanded.value.add(mod.path)
})
function toggle(path: string) {
  expanded.value.has(path) ? expanded.value.delete(path) : expanded.value.add(path)
}
function isOpen(path: string) {
  return query.value.trim() ? true : expanded.value.has(path)
}
</script>

<template>
  <nav class="lesson-sidebar" aria-label="Lessons">
    <div class="sidebar-search">
      <Icon name="lucide:search" class="sidebar-search-icon" />
      <input v-model="query" type="search" placeholder="Search lessons…" aria-label="Search lessons">
    </div>

    <p v-if="query.trim() && !filtered.length" class="sidebar-empty">No lessons match "{{ query }}".</p>

    <div v-for="mod in filtered" :key="mod.path" class="sidebar-module">
      <button
        type="button"
        class="sidebar-module-header"
        :class="{ active: isActiveModule(mod as any) }"
        @click="toggle(mod.path)"
      >
        <Icon v-if="(mod as any).icon" :name="(mod as any).icon" class="sidebar-module-icon" />
        <span class="sidebar-module-title">{{ mod.title }}</span>
        <Icon
          name="lucide:chevron-down"
          class="sidebar-chevron"
          :class="{ open: isOpen(mod.path) }"
        />
      </button>
      <ul v-show="isOpen(mod.path)" class="sidebar-lesson-list">
        <li v-for="lesson in mod.children ?? []" :key="lesson.path">
          <NuxtLink :to="lesson.path" class="sidebar-lesson-link" :class="{ active: isActive(lesson.path) }">
            {{ lesson.title }}
          </NuxtLink>
        </li>
      </ul>
    </div>
  </nav>
</template>

<style scoped>
.lesson-sidebar { display: flex; flex-direction: column; gap: 0.15rem; }

.sidebar-search {
  position: relative;
  margin-bottom: 0.75rem;
}
.sidebar-search-icon {
  position: absolute;
  left: 0.6rem;
  top: 50%;
  transform: translateY(-50%);
  color: var(--fg-faint);
  font-size: 0.85rem;
  pointer-events: none;
}
.sidebar-search input {
  width: 100%;
  padding: 0.45rem 0.6rem 0.45rem 1.8rem;
  border: 1px solid var(--line-default);
  border-radius: 6px;
  background: var(--bg-surface);
  color: var(--fg-default);
  font: inherit;
  font-size: 0.85rem;
}
.sidebar-search input::-webkit-search-cancel-button { cursor: pointer; }
.sidebar-empty { font-size: 0.82rem; color: var(--fg-faint); padding: 0.3rem 0.6rem; }

.sidebar-module-header {
  width: 100%;
  display: flex;
  align-items: center;
  gap: 0.5rem;
  background: none;
  border: none;
  padding: 0.5rem 0.6rem;
  border-radius: 6px;
  font: inherit;
  font-weight: 600;
  font-size: 0.85rem;
  color: var(--fg-muted);
  cursor: pointer;
  text-align: left;
}
.sidebar-module-header:hover { background: var(--hover-wash); color: var(--fg-default); }
.sidebar-module-header.active { color: var(--fg-default); }
.sidebar-module-icon { flex: none; font-size: 1rem; color: var(--fg-accent); }
.sidebar-module-title { flex: 1; }
.sidebar-chevron { flex: none; font-size: 0.85rem; transition: transform 0.15s ease; }
.sidebar-chevron.open { transform: rotate(180deg); }

.sidebar-lesson-list {
  list-style: none;
  margin: 0.1rem 0 0.5rem;
  padding: 0;
  border-left: 1px solid var(--line-subtle);
  margin-left: 1.05rem;
}
.sidebar-lesson-link {
  display: block;
  padding: 0.35rem 0.75rem;
  margin-left: -1px;
  border-left: 2px solid transparent;
  font-size: 0.8rem;
  color: var(--fg-subtle);
  text-decoration: none;
  line-height: 1.35;
}
.sidebar-lesson-link:hover { color: var(--fg-default); }
.sidebar-lesson-link.active {
  color: var(--fg-accent);
  border-left-color: var(--accent);
  font-weight: 600;
  background: var(--accent-soft);
}
</style>
