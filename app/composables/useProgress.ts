export function useProgress() {
  const completedSlugs = useState<string[]>('progress:slugs', () => [])
  const loaded = useState<boolean>('progress:loaded', () => false)

  async function refresh() {
    const { completedSlugs: slugs } = await $fetch<{ completedSlugs: string[] }>('/api/progress')
    completedSlugs.value = slugs
    loaded.value = true
    return slugs
  }

  function isComplete(slug: string) {
    return completedSlugs.value.includes(slug)
  }

  async function markComplete(slug: string) {
    if (isComplete(slug)) return
    await $fetch(`/api/progress/${slug}`, { method: 'POST' })
    completedSlugs.value = [...completedSlugs.value, slug]
  }

  if (import.meta.client && !loaded.value) refresh()

  return { completedSlugs, loaded, refresh, isComplete, markComplete }
}
