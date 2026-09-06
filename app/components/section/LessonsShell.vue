<script setup lang="ts">
// The shared docs-site frame for /lessons (the catalogue) and every
// individual lesson reader (flat routes like /data-model/data-modeling):
// a sticky left nav tree, the page content in the middle, and an optional
// sticky right "on this page" TOC (only lesson readers pass one — the
// catalogue page just omits the #toc slot).
const sidebarOpen = ref(false)
</script>

<template>
  <div class="lessons-shell">
    <button type="button" class="mobile-nav-toggle" @click="sidebarOpen = !sidebarOpen">
      <Icon name="lucide:panel-left" />
      Lessons menu
    </button>

    <aside class="lessons-sidebar" :class="{ open: sidebarOpen }">
      <LessonSidebar @click="sidebarOpen = false" />
    </aside>

    <div v-if="sidebarOpen" class="sidebar-scrim" @click="sidebarOpen = false" />

    <div class="lessons-main"><slot /></div>

    <aside v-if="$slots.toc" class="lessons-toc-rail"><slot name="toc" /></aside>
  </div>
</template>

<style scoped>
.lessons-shell {
  display: grid;
  grid-template-columns: 16.5rem minmax(0, 1fr) 14rem;
  gap: 2.5rem;
  align-items: start;
  max-width: 90rem;
  margin-inline: auto;
  padding: 2rem 1.5rem 4rem;
}

.mobile-nav-toggle { display: none; }

.lessons-sidebar {
  position: sticky;
  top: 5rem;
  max-height: calc(100vh - 6rem);
  overflow-y: auto;
  padding-right: 0.5rem;
}

.lessons-main { min-width: 0; }

.lessons-toc-rail {
  position: sticky;
  top: 5rem;
  max-height: calc(100vh - 6rem);
  overflow-y: auto;
}

.sidebar-scrim { display: none; }

@media (max-width: 1080px) {
  .lessons-shell { grid-template-columns: 15.5rem minmax(0, 1fr); }
  .lessons-toc-rail { display: none; }
}

@media (max-width: 800px) {
  .lessons-shell {
    grid-template-columns: minmax(0, 1fr);
    padding-top: 1rem;
  }
  .mobile-nav-toggle {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    width: 100%;
    background: var(--bg-surface);
    border: 1px solid var(--line-default);
    border-radius: 8px;
    padding: 0.65rem 1rem;
    font: inherit;
    font-weight: 600;
    color: var(--fg-default);
    margin-bottom: 1rem;
  }
  .lessons-sidebar {
    position: fixed;
    top: 0;
    left: 0;
    bottom: 0;
    width: 16.5rem;
    max-height: none;
    background: var(--bg-surface);
    border-right: 1px solid var(--line-default);
    padding: 1.25rem 1rem;
    transform: translateX(-100%);
    transition: transform 0.2s ease;
    z-index: 30;
  }
  .lessons-sidebar.open { transform: translateX(0); }
  .sidebar-scrim {
    display: block;
    position: fixed;
    inset: 0;
    background: var(--bg-scrim);
    z-index: 20;
  }
}
</style>
