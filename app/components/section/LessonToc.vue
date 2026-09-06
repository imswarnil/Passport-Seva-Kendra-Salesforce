<script setup lang="ts">
interface TocLink { id: string, text: string, depth: number, children?: TocLink[] }
const props = defineProps<{ links: TocLink[] }>()

// Scroll-spy: highlight whichever heading is currently nearest the top of
// the viewport. Flattened once since nesting depth doesn't matter for this.
function flatten(links: TocLink[]): TocLink[] {
  return links.flatMap(l => [l, ...(l.children ? flatten(l.children) : [])])
}
const flat = computed(() => flatten(props.links))
const activeId = ref<string>()

let observer: IntersectionObserver | undefined
onMounted(() => {
  const headings = flat.value
    .map(l => document.getElementById(l.id))
    .filter((el): el is HTMLElement => !!el)

  observer = new IntersectionObserver(
    (entries) => {
      const visible = entries.filter(e => e.isIntersecting)
      if (visible.length) activeId.value = visible[0].target.id
    },
    { rootMargin: '-80px 0px -70% 0px' }
  )
  headings.forEach(el => observer!.observe(el))
})
onBeforeUnmount(() => observer?.disconnect())
</script>

<template>
  <nav v-if="links.length" class="lesson-toc" aria-label="On this page">
    <p class="toc-heading"><Icon name="lucide:list" />On this page</p>
    <ul>
      <li v-for="link in links" :key="link.id" :class="`depth-${link.depth}`">
        <a :href="`#${link.id}`" :class="{ active: activeId === link.id }">{{ link.text }}</a>
        <ul v-if="link.children?.length">
          <li v-for="child in link.children" :key="child.id" :class="`depth-${child.depth}`">
            <a :href="`#${child.id}`" :class="{ active: activeId === child.id }">{{ child.text }}</a>
          </li>
        </ul>
      </li>
    </ul>
  </nav>
</template>

<style scoped>
.lesson-toc { font-size: 0.85rem; }
.toc-heading {
  display: flex;
  align-items: center;
  gap: 0.4rem;
  font-size: 0.75rem;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  font-weight: 700;
  color: var(--fg-faint);
  margin: 0 0 0.6rem;
}
ul { list-style: none; margin: 0; padding: 0; }
li.depth-3 { margin-left: 0.85rem; }
a {
  display: block;
  padding: 0.3rem 0 0.3rem 0.7rem;
  border-left: 2px solid var(--line-subtle);
  color: var(--fg-subtle);
  text-decoration: none;
  line-height: 1.35;
}
a:hover { color: var(--fg-default); }
a.active { color: var(--fg-accent); border-left-color: var(--accent); font-weight: 600; }
</style>
