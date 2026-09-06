<script setup lang="ts">
const route = useRoute()
const router = useRouter()
const object = route.params.object as string

interface QueryResult {
  records: Record<string, unknown>[]
  page: number
  pageSize: number
  hasMore: boolean
  hasPrev: boolean
}

const page = computed(() => Math.max(1, Number.parseInt(String(route.query.page ?? '1'), 10) || 1))

const { data, error, pending } = await useFetch<QueryResult>(
  () => `/api/demo-org/${object}/records`,
  { query: { page }, watch: [page] }
)

const columns = computed(() => {
  const first = data.value?.records[0]
  return first ? Object.keys(first).filter(k => k !== 'attributes') : []
})

function goToPage(p: number) {
  router.push({ query: { ...route.query, page: p > 1 ? p : undefined } })
}
</script>

<template>
  <div class="container demo-org">
    <div class="banner">
      <Icon name="lucide:shield-alert" class="banner-icon" />
      <span><strong>Live read-only view of a real Salesforce org.</strong> Nothing here can be edited, created, or deleted.</span>
    </div>

    <nav class="breadcrumb">
      <NuxtLink to="/demo-org"><Icon name="lucide:arrow-left" /> All objects</NuxtLink>
    </nav>
    <h1><Icon name="lucide:table-2" class="title-icon" />{{ object }}</h1>

    <div v-if="pending" class="state-block">
      <Icon name="lucide:loader-circle" class="spin" /> Loading records…
    </div>
    <div v-else-if="error" class="state-block demo-org-error">
      <Icon name="lucide:circle-alert" /> Couldn't load {{ object }} ({{ error.statusMessage || error.message }}).
    </div>
    <div v-else-if="!data?.records.length" class="state-block">
      <Icon name="lucide:inbox" /> No records visible to the demo user{{ page > 1 ? ' on this page' : '' }}.
    </div>

    <template v-else>
      <div class="table-wrap">
        <table>
          <thead>
            <tr><th v-for="col in columns" :key="col">{{ col }}</th></tr>
          </thead>
          <tbody>
            <tr v-for="record in data.records" :key="record.Id as string">
              <td v-for="col in columns" :key="col">
                <NuxtLink v-if="col === 'Id'" :to="`/demo-org/${object}/${record.Id}`" class="record-link">
                  {{ record[col] }}
                </NuxtLink>
                <span v-else-if="typeof record[col] === 'boolean'" class="bool-cell">
                  <Icon :name="record[col] ? 'lucide:check' : 'lucide:x'" />
                </span>
                <span v-else>{{ record[col] ?? '—' }}</span>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <nav class="pagination">
        <button type="button" class="btn btn-ghost" :disabled="!data.hasPrev" @click="goToPage(page - 1)">
          <Icon name="lucide:arrow-left" /> Previous
        </button>
        <span class="pagination-page">Page {{ page }}</span>
        <button type="button" class="btn btn-ghost" :disabled="!data.hasMore" @click="goToPage(page + 1)">
          Next <Icon name="lucide:arrow-right" />
        </button>
      </nav>
    </template>
  </div>
</template>

<style scoped>
.demo-org { padding-block: 2rem; }

.banner {
  display: flex;
  gap: 0.75rem;
  background: var(--warning-bg);
  color: var(--warning-fg);
  border: 1px solid var(--warning-line);
  border-radius: 8px;
  padding: 0.9rem 1.1rem;
  margin-bottom: 1.5rem;
  line-height: 1.5;
}
.banner-icon { flex: none; font-size: 1.25rem; margin-top: 0.1em; }

.breadcrumb { margin-bottom: 0.75rem; }
.breadcrumb a { display: inline-flex; align-items: center; gap: 0.35rem; color: var(--fg-link); text-decoration: none; font-size: 0.9rem; }

h1 { display: flex; align-items: center; gap: 0.6rem; font-family: ui-monospace, monospace; }
.title-icon { color: var(--fg-accent); }

.state-block {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  color: var(--fg-muted);
  padding: 2rem 0;
}
.demo-org-error { color: var(--danger-fg); }
.spin { animation: spin 1s linear infinite; }
@keyframes spin { to { transform: rotate(360deg); } }

.table-wrap { overflow-x: auto; border: 1px solid var(--line-default); border-radius: 8px; }
table { width: 100%; border-collapse: collapse; font-size: 0.9rem; }
th, td { text-align: left; padding: 0.55rem 0.75rem; border-bottom: 1px solid var(--line-subtle); white-space: nowrap; }
th { background: var(--bg-muted); color: var(--fg-muted); font-weight: 600; }
.record-link { color: var(--fg-link); font-family: ui-monospace, monospace; font-size: 0.85rem; }
.bool-cell { display: inline-flex; color: var(--fg-subtle); }

.pagination {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 1.25rem;
  margin-top: 1.5rem;
}
.pagination-page { font-size: 0.85rem; color: var(--fg-subtle); }
.pagination .btn:disabled { opacity: 0.4; cursor: not-allowed; }
</style>
