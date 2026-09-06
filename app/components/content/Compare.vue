<script setup lang="ts">
defineProps<{
  leftTitle: string
  leftItems: string[]
  rightTitle: string
  rightItems: string[]
}>()
</script>

<template>
  <div class="compare">
    <div class="compare-col compare-bad">
      <p class="compare-heading">{{ leftTitle }}</p>
      <ul>
        <li v-for="(item, i) in leftItems" :key="i">{{ item }}</li>
      </ul>
    </div>
    <div class="compare-col compare-good">
      <p class="compare-heading">{{ rightTitle }}</p>
      <ul>
        <li v-for="(item, i) in rightItems" :key="i">{{ item }}</li>
      </ul>
    </div>
  </div>
</template>

<style scoped>
.compare {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 1rem;
  margin: 1.5rem 0;
}
@media (max-width: 640px) {
  .compare { grid-template-columns: 1fr; }
}
.compare-col {
  border-radius: 8px;
  padding: 1rem 1.25rem;
  border: 1px solid var(--line-default);
}
.compare-bad { background: var(--danger-bg); border-color: var(--danger-line); }
.compare-good { background: var(--success-bg); border-color: var(--success-line); }
.compare-heading { margin: 0 0 0.5em; font-weight: 600; }
.compare-bad .compare-heading { color: var(--danger-fg); }
.compare-good .compare-heading { color: var(--success-fg); }
.compare-col ul { margin: 0; padding-left: 1.1em; }
.compare-bad li { color: var(--danger-fg); }
.compare-good li { color: var(--success-fg); }
.compare-col li + li { margin-top: 0.4em; }
</style>
