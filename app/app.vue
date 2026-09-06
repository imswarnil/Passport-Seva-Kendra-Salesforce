<script setup lang="ts">
useHead({
  titleTemplate: title => (title ? `${title} — Salesforce Passport` : 'Salesforce Passport'),
  link: [{ rel: 'icon', type: 'image/svg+xml', href: '/favicon.svg' }],
  // Sitewide WebSite + Course JSON-LD. Raw <script type="application/ld+json">
  // rather than a schema-org module — one more dependency isn't worth it for
  // two static objects that never change per-page (lesson pages add their
  // own LearningResource block on top of this, see [...slug].vue).
  script: [{
    type: 'application/ld+json',
    innerHTML: JSON.stringify({
      '@context': 'https://schema.org',
      '@graph': [
        {
          '@type': 'WebSite',
          name: 'Salesforce Passport',
          url: 'https://salesforce.imswarnil.com',
          description: 'Learn Salesforce by building Passport Seva Kendra — a complete, deployable Salesforce app taught in the open.'
        },
        {
          '@type': 'Course',
          name: 'Salesforce Passport',
          description: 'A complete, deployable Salesforce build — 17 objects, real Apex, real sharing rules — walked through lesson by lesson.',
          provider: { '@type': 'Person', name: 'Swarnil', url: 'https://imswarnil.com' },
          isAccessibleForFree: true
        }
      ]
    })
  }]
})
</script>

<template>
  <NuxtLayout>
    <NuxtPage />
  </NuxtLayout>
</template>
