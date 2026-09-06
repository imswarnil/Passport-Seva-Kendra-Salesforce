// https://nuxt.com/docs/api/configuration/nuxt-config
//
// Deploys to Cloudflare Workers (not Pages, not `nuxt generate`) because the
// platform needs a real server: session-based accounts, a live Neon-backed
// database for progress/comments/guestbook/resources, and a read-only proxy
// to the Passport Seva Kendra Salesforce org. See SETUP.md for what has to be
// provisioned (Neon, Cloudflare R2 + secrets, the Salesforce JWT integration
// user) before any of that server code has something to talk to.
export default defineNuxtConfig({
  modules: [
    '@nuxt/content',
    '@nuxt/icon',
    '@nuxt/image',
    '@vueuse/nuxt'
  ],

  icon: {
    // Real inline <svg>, not the CSS-class mode (mode:'css' emits
    // <span class="iconify i-lucide:x">, which needs a runtime stylesheet
    // to actually paint anything — fragile, and invisible if that
    // stylesheet ever fails to load). 'svg' renders the glyph directly in
    // the SSR HTML, no extra request or client JS required to see it.
    mode: 'svg',
    serverBundle: { collections: ['lucide'] }
  },

  devtools: { enabled: true },

  css: ['~/assets/css/main.css'],

  // Flat component names regardless of subfolder (content/, section/,
  // community/) — every component built across content/lessons, the
  // section/module UI, and the auth/community backend assumed bare names
  // (<ObjectRef>, <Hero>, <CommentThread>, …) with no collisions, so this
  // avoids Nuxt's default folder-prefixing (<CommunityCommentThread>, etc.)
  // rather than renaming every usage site to match it.
  components: [{ path: '~/components', pathPrefix: false }],

  site: {
    url: 'https://salesforce.imswarnil.com',
    name: 'Salesforce Passport — learn Salesforce by building Passport Seva Kendra'
  },

  content: {
    build: {
      markdown: {
        toc: { depth: 3, searchDepth: 3 }
      }
    },
    experimental: {
      sqliteConnector: 'native'
    }
  },

  runtimeConfig: {
    // Server-only. Set as `wrangler secret put <NAME>` in production; read
    // from `.env` in dev (see .env.example). Never exposed to the client.
    databaseUrl: '',
    sessionSecret: '',
    sfLoginUrl: 'https://login.salesforce.com',
    sfClientId: '',
    sfUsername: '',
    sfPrivateKey: '',
    public: {
      siteUrl: 'https://salesforce.imswarnil.com',
      demoOrgEnabled: false
    }
  },

  nitro: {
    experimental: { wasm: true }
  },

  // The Cloudflare preset only applies to `nuxt build` (→ `pnpm run
  // deploy`/CI). Setting it unconditionally also makes `nuxt dev` route
  // through a Workerd emulation proxy in front of Vite — which is what was
  // silently breaking the client entry module's dynamic import in dev
  // (`Failed to fetch dynamically imported module: .../entry.js`) and the
  // Vite HMR websocket (it kept trying port 5173 instead of 3000). `nuxt
  // dev` now runs on Nitro's plain node-dev server, same as any other Nuxt
  // app; `.output/server/index.mjs` is still the Cloudflare Worker entry at
  // build time, which is all `wrangler.jsonc` and `pnpm run deploy` need.
  $production: {
    nitro: { preset: 'cloudflare_module' }
  },

  compatibilityDate: '2025-09-06'
})
