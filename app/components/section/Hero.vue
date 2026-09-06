<script setup lang="ts">
defineProps<{
  icon?: string
  eyebrow?: string
  title: string
  description: string
}>()
</script>

<template>
  <section class="hero" :class="{ 'hero-split': !!$slots.illustration }">
    <div class="hero-copy">
      <div v-if="icon" class="hero-icon">
        <Icon :name="icon" />
      </div>
      <p v-if="eyebrow" class="hero-eyebrow">{{ eyebrow }}</p>
      <h1 class="hero-title">{{ title }}</h1>
      <p class="hero-description">{{ description }}</p>
      <div class="hero-actions">
        <slot name="actions" />
      </div>
    </div>
    <div v-if="$slots.illustration" class="hero-illustration-slot">
      <slot name="illustration" />
    </div>
  </section>
</template>

<style scoped>
.hero {
  padding: 4rem 0 2rem;
  text-align: center;
  max-width: 42rem;
  margin-inline: auto;
}
.hero-icon {
  width: 3.5rem;
  height: 3.5rem;
  margin: 0 auto 1.25rem;
  display: flex;
  align-items: center;
  justify-content: center;
  border-radius: 14px;
  background: var(--brand-navy, var(--accent-soft));
  color: var(--gold-400);
  font-size: 1.75rem;
}
.hero-eyebrow {
  font-size: 0.8rem;
  letter-spacing: 0.08em;
  text-transform: uppercase;
  color: var(--fg-accent);
  font-weight: 600;
  margin: 0 0 0.75em;
}
.hero-title {
  font-size: clamp(2rem, 4vw, 3rem);
  margin: 0 0 0.5em;
}
.hero-description {
  font-size: 1.1rem;
  color: var(--fg-muted);
  margin: 0 0 2em;
}
.hero-actions {
  display: flex;
  justify-content: center;
  gap: 0.75rem;
  flex-wrap: wrap;
}

/* Two-column mode, used when an #illustration slot is passed (the
   homepage). Text stays centered until the split actually kicks in at
   1000px, so a narrow viewport never sees a lopsided single column. */
.hero-split {
  max-width: 72rem;
  display: grid;
  grid-template-columns: 1fr;
}
@media (min-width: 1000px) {
  .hero-split {
    grid-template-columns: 1.1fr 1fr;
    align-items: center;
    gap: 3rem;
    text-align: left;
  }
  .hero-split .hero-icon { margin-inline: 0; }
  .hero-split .hero-actions { justify-content: flex-start; }
}
.hero-illustration-slot { order: -1; }
@media (min-width: 1000px) {
  .hero-illustration-slot { order: 1; }
}
</style>
