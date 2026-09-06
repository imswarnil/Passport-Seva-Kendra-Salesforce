<template>
  <blockquote class="pull-quote">
    <MDCSlot :use="$slots.default" unwrap="p" />
  </blockquote>
</template>

<style scoped>
.pull-quote {
  margin: 2rem 0;
  padding: 1rem 1.5rem;
  border-left: 3px solid var(--accent);
  background: var(--accent-soft);
  border-radius: 0 8px 8px 0;
  font-size: 1.1rem;
  font-weight: 500;
}
.pull-quote :deep(p) {
  margin: 0;
  color: var(--accent-soft-fg);
}
</style>
