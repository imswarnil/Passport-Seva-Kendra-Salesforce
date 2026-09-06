<script setup lang="ts">
const route = useRoute()
const object = route.params.object as string
const id = route.params.id as string

const { data: record, error, pending } = await useFetch<Record<string, unknown>>(`/api/demo-org/${object}/${id}`)

const fields = computed(() => record.value ? Object.keys(record.value).filter(k => k !== 'attributes') : [])
</script>

<template>
  <div class="container demo-org">
    <div class="banner">
      <Icon name="lucide:shield-alert" class="banner-icon" />
      <span><strong>Live read-only view of a real Salesforce org.</strong> Nothing here can be edited, created, or deleted.</span>
    </div>

    <nav class="breadcrumb">
      <NuxtLink to="/demo-org"><Icon name="lucide:table-2" /> Objects</NuxtLink>
      <Icon name="lucide:chevron-right" class="crumb-sep" />
      <NuxtLink :to="`/demo-org/${object}`">{{ object }}</NuxtLink>
    </nav>

    <div v-if="pending" class="state-block">
      <Icon name="lucide:loader-circle" class="spin" /> Loading record…
    </div>
    <div v-else-if="error" class="state-block demo-org-error">
      <Icon name="lucide:circle-alert" /> Couldn't load this record ({{ error.statusMessage || error.message }}).
    </div>

    <template v-else>
      <h1><Icon name="lucide:file-text" class="title-icon" />{{ record?.Name ?? id }}</h1>
      <dl class="record">
        <template v-for="field in fields" :key="field">
          <dt>{{ field }}</dt>
          <dd>
            <span v-if="typeof record?.[field] === 'boolean'" class="bool-cell">
              <Icon :name="record[field] ? 'lucide:check' : 'lucide:x'" />
            </span>
            <span v-else>{{ record?.[field] ?? '—' }}</span>
          </dd>
        </template>
      </dl>
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

.breadcrumb { display: flex; align-items: center; gap: 0.4rem; margin-bottom: 1rem; font-size: 0.9rem; }
.breadcrumb a { display: inline-flex; align-items: center; gap: 0.35rem; color: var(--fg-link); text-decoration: none; }
.crumb-sep { color: var(--fg-faint); font-size: 0.8rem; }

h1 { display: flex; align-items: center; gap: 0.6rem; margin-bottom: 1.25rem; }
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

.record {
  display: grid;
  grid-template-columns: max-content 1fr;
  gap: 0.6rem 1.5rem;
  background: var(--bg-surface);
  border: 1px solid var(--line-default);
  border-radius: 10px;
  padding: 1.25rem;
}
dt { color: var(--fg-subtle); font-family: ui-monospace, monospace; font-size: 0.85rem; }
dd { margin: 0; color: var(--fg-default); }
.bool-cell { display: inline-flex; color: var(--fg-subtle); }
</style>
