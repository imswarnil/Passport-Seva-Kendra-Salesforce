<script setup lang="ts">
interface ObjectEntry { object: string, fields: string[] }

const { data: objects, error, pending } = await useFetch<ObjectEntry[]>('/api/demo-org/objects')
</script>

<template>
  <div class="container demo-org">
    <div class="banner">
      <Icon name="lucide:shield-alert" class="banner-icon" />
      <span>
        <strong>Live read-only view of a real Salesforce org.</strong>
        Nothing here can be edited, created, or deleted — this Worker holds a
        permission set that can only read, and only these six objects.
      </span>
    </div>

    <h1>Browse the Passport Seva Kendra org</h1>
    <p>
      Pick an object to page through real records from the live dev org,
      20 at a time, through the same field allowlist documented in
      <code>server/utils/demo-org-allowlist.ts</code>.
    </p>

    <div v-if="pending" class="state-block">
      <Icon name="lucide:loader-circle" class="spin" /> Loading objects…
    </div>
    <div v-else-if="error" class="demo-org-error state-block">
      <Icon name="lucide:circle-alert" />
      The demo org isn't reachable right now
      ({{ error.statusMessage || error.message }}). If you're the site owner,
      see docs/SETUP_ORG.md.
    </div>

    <div v-else class="object-grid">
      <NuxtLink
        v-for="entry in objects"
        :key="entry.object"
        :to="`/demo-org/${entry.object}`"
        class="object-card"
      >
        <span class="object-icon"><Icon name="lucide:table-2" /></span>
        <span class="object-name">{{ entry.object }}</span>
        <span class="object-fields">{{ entry.fields.length }} visible fields</span>
      </NuxtLink>
    </div>
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

.state-block {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  color: var(--fg-muted);
  padding: 1.5rem 0;
}
.spin { animation: spin 1s linear infinite; }
@keyframes spin { to { transform: rotate(360deg); } }

.demo-org-error {
  background: var(--danger-bg);
  color: var(--danger-fg);
  border: 1px solid var(--danger-line);
  border-radius: 8px;
  padding: 0.9rem 1.1rem;
}

.object-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(200px, 1fr));
  gap: 1rem;
  margin-top: 1.5rem;
}

.object-card {
  display: flex;
  flex-direction: column;
  gap: 0.25rem;
  background: var(--bg-surface);
  border: 1px solid var(--line-default);
  border-radius: 10px;
  padding: 1rem;
  text-decoration: none;
}
.object-card:hover { border-color: var(--accent); background: var(--hover-wash); }

.object-icon {
  width: 2rem;
  height: 2rem;
  display: flex;
  align-items: center;
  justify-content: center;
  border-radius: 7px;
  background: var(--accent-soft);
  color: var(--accent-soft-fg);
  font-size: 1.05rem;
  margin-bottom: 0.15rem;
}
.object-name { font-weight: 600; color: var(--fg-default); font-family: ui-monospace, monospace; }
.object-fields { color: var(--fg-subtle); font-size: 0.85rem; }
</style>
