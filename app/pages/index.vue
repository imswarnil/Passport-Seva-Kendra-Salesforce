<script setup lang="ts">
const { data: lessons } = await useAsyncData('home-lessons', () => queryCollection('lessons').all())

// Excludes each module's `.navigation.yml` row (see content.config.ts) — it
// shares this collection but is never a real lesson and never sets a
// description.
const realLessons = computed(() => (lessons.value ?? []).filter(l => l.description))

const modules = computed(() =>
  LESSON_MODULES.map(m => ({
    ...m,
    to: `/${m.slug}`,
    lessonCount: realLessons.value.filter(l => l.path.startsWith(`/${m.slug}/`)).length
  }))
)
</script>

<template>
  <div>
    <div class="container">
      <Hero
        icon="lucide:stamp"
        eyebrow="A Salesforce org, taught in the open"
        title="Salesforce Passport"
        description="Learn Salesforce by building Passport Seva Kendra — a complete, deployable app: 17 objects, real Apex, real sharing rules — walked through lesson by lesson, with a read-only copy of the actual org you can click around in."
      >
        <template #actions>
          <NuxtLink to="/lessons" class="btn btn-primary">Start learning</NuxtLink>
          <NuxtLink to="/demo-org" class="btn btn-ghost">Try the org →</NuxtLink>
        </template>
        <template #illustration>
          <HeroIllustration />
        </template>
      </Hero>
    </div>

    <div class="container-wide">
      <SectionDivider label="Curriculum" />
      <div class="module-grid">
        <ModuleCard
          v-for="m in modules"
          :key="m.slug"
          :icon="m.icon"
          :title="m.title"
          :description="m.description"
          :to="m.to"
          :lesson-count="m.lessonCount"
        />
      </div>
    </div>

    <div class="container-wide">
      <SectionDivider label="The data model" />
      <div class="section-intro">
        <h2><Icon name="lucide:database" class="section-icon" />Few objects, many fields</h2>
        <p>
          The whole application lifecycle lives on <strong>one</strong> object driven by a
          <code>Status__c</code> picklist and record types — not a new object per stage. Eight of
          the seventeen deployed objects, as a sample:
        </p>
      </div>
      <div class="object-grid">
        <ObjectPreviewCard
          v-for="obj in DATA_MODEL_PREVIEW"
          :key="obj.api"
          :label="obj.label"
          :api="obj.api"
          :relationship="obj.relationship"
          :purpose="obj.purpose"
        />
      </div>
      <NuxtLink to="/data-model/the-object-catalogue" class="btn btn-ghost see-all">
        See all 17 objects <Icon name="lucide:arrow-right" />
      </NuxtLink>
    </div>

    <div class="container-wide">
      <SectionDivider label="The lifecycle" />
      <div class="section-intro">
        <h2><Icon name="lucide:workflow" class="section-icon" />One record, ten stages</h2>
        <p>A half-finished application is the same object in <code>Draft</code> status — not a different object. This is <code>Passport_Application__c.Status__c</code>, the field the entire build turns on:</p>
      </div>
      <Stages
        :stages="PASSPORT_STATUS_STAGES"
        :terminal="PASSPORT_STATUS_TERMINAL"
        current="Police Verification"
      />
      <NuxtLink to="/foundations/the-journey" class="btn btn-ghost see-all">
        Walk the full journey <Icon name="lucide:arrow-right" />
      </NuxtLink>
    </div>

    <div class="container-wide">
      <SectionDivider label="Who it's for" />
      <div class="section-intro">
        <h2><Icon name="lucide:users" class="section-icon" />Eight personas, one of whom never logs in</h2>
        <p>Every permission set, queue and sharing rule in this build traces back to one of these people — including the applicant, who never gets a Salesforce login at all.</p>
      </div>
      <div class="persona-grid">
        <PersonaCard
          v-for="p in PERSONAS"
          :key="p.name"
          :icon="p.icon"
          :name="p.name"
          :role="p.role"
          :app="p.app"
          :owns="p.owns"
        />
      </div>
      <NuxtLink to="/foundations/personas" class="btn btn-ghost see-all">
        Read the full cast <Icon name="lucide:arrow-right" />
      </NuxtLink>
    </div>

    <div class="container">
      <SectionDivider label="Why public" />
      <section class="why-section">
        <div class="why-col">
          <div class="why-icon"><Icon name="lucide:eye" /></div>
          <h2>Why this is public</h2>
          <p>I'm building this myself to learn Salesforce properly, not just to pass an exam — and sharing it in the open so anyone else learning the platform can follow along, borrow from it, or point out where I got something wrong. Most Salesforce learning material is either abstract (Trailhead modules with no real stakes) or hidden behind a client NDA. This is neither: a real, opinionated build — with its actual mistakes, actual trade-offs, and actual metadata — left open so the reasoning is checkable, not just the result.</p>
        </div>
        <div class="why-col">
          <div class="why-icon"><Icon name="lucide:download-cloud" /></div>
          <h2>Install it yourself</h2>
          <p>The whole org is SFDX source, deployable to your own Developer Edition org with the Salesforce CLI. Read the lessons, then read the actual files they're describing, then deploy them and click around for real.</p>
          <NuxtLink to="/foundations/the-problem" class="btn btn-ghost">Read the setup guide →</NuxtLink>
        </div>
      </section>
    </div>

    <div class="container">
      <SectionDivider label="Or just look" />
      <section class="demo-cta">
        <div class="demo-cta-icon"><Icon name="lucide:mouse-pointer-click" /></div>
        <h2>Don't want to install anything?</h2>
        <p>Sign in with a demo account and click through a live, read-only copy of the actual org — every object, every record page, exactly as it's deployed. You can look at everything and break nothing.</p>
        <NuxtLink to="/demo-org" class="btn btn-primary">Open the read-only org →</NuxtLink>
      </section>
    </div>
  </div>
</template>

<style scoped>
.module-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(15rem, 1fr));
  gap: 1rem;
  margin-bottom: 3rem;
}

.section-intro { max-width: 42rem; margin-bottom: 1.5rem; }
.section-intro h2 {
  display: flex;
  align-items: center;
  gap: 0.55rem;
  font-size: 1.3rem;
}
.section-icon { color: var(--fg-accent); }
.section-intro code {
  background: var(--bg-muted);
  border-radius: 4px;
  padding: 0.05em 0.4em;
  font-size: 0.9em;
}

.object-grid,
.persona-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(16rem, 1fr));
  gap: 1rem;
  margin-bottom: 1.5rem;
}

.see-all { margin-bottom: 3rem; }

.why-section {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 2rem;
  margin-bottom: 3rem;
}
.why-section h2 { font-size: 1.25rem; }
.why-icon {
  width: 2.5rem;
  height: 2.5rem;
  display: flex;
  align-items: center;
  justify-content: center;
  border-radius: 10px;
  background: var(--accent-soft);
  color: var(--accent-soft-fg);
  font-size: 1.25rem;
  margin-bottom: 1rem;
}
@media (max-width: 720px) {
  .why-section { grid-template-columns: 1fr; }
}

.demo-cta {
  text-align: center;
  max-width: 36rem;
  margin: 0 auto 3rem;
}
.demo-cta h2 { font-size: 1.4rem; }
.demo-cta-icon {
  width: 3rem;
  height: 3rem;
  margin: 0 auto 1rem;
  display: flex;
  align-items: center;
  justify-content: center;
  border-radius: 50%;
  background: var(--accent-soft);
  color: var(--accent-soft-fg);
  font-size: 1.5rem;
}
</style>
