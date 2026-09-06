<script setup lang="ts">
const { user, logout } = useAuth()
const mobileNavOpen = ref(false)
const route = useRoute()
watch(() => route.fullPath, () => { mobileNavOpen.value = false })
</script>

<template>
  <div class="shell">
    <header class="site-header">
      <div class="container header-inner">
        <NuxtLink to="/" class="brand">
          <span class="brand-mark"><Icon name="lucide:stamp" /></span>
          <span class="brand-name">Salesforce Passport</span>
        </NuxtLink>
        <nav class="main-nav">
          <NuxtLink to="/lessons"><Icon name="lucide:rocket" /> Start Here</NuxtLink>
          <NuxtLink to="/demo-org"><Icon name="lucide:mouse-pointer-click" /> Try the org</NuxtLink>
          <NuxtLink to="/resources"><Icon name="lucide:library" /> Resources</NuxtLink>
          <NuxtLink to="/guestbook"><Icon name="lucide:message-square-heart" /> Guestbook</NuxtLink>
        </nav>
        <div class="auth-links">
          <template v-if="user">
            <NuxtLink to="/dashboard" class="btn btn-ghost">{{ user.displayName }}</NuxtLink>
            <button class="btn btn-ghost" type="button" @click="logout">Sign out</button>
          </template>
          <template v-else>
            <NuxtLink to="/login" class="btn btn-ghost">Log in</NuxtLink>
            <NuxtLink to="/signup" class="btn btn-primary">Sign up</NuxtLink>
          </template>
        </div>
        <button
          type="button"
          class="hamburger"
          :aria-expanded="mobileNavOpen"
          aria-label="Toggle menu"
          @click="mobileNavOpen = !mobileNavOpen"
        >
          <Icon :name="mobileNavOpen ? 'lucide:x' : 'lucide:menu'" />
        </button>
      </div>

      <div v-if="mobileNavOpen" class="mobile-nav">
        <NuxtLink to="/lessons"><Icon name="lucide:rocket" /> Start Here</NuxtLink>
        <NuxtLink to="/demo-org"><Icon name="lucide:mouse-pointer-click" /> Try the org</NuxtLink>
        <NuxtLink to="/resources"><Icon name="lucide:library" /> Resources</NuxtLink>
        <NuxtLink to="/guestbook"><Icon name="lucide:message-square-heart" /> Guestbook</NuxtLink>
        <hr>
        <template v-if="user">
          <NuxtLink to="/dashboard"><Icon name="lucide:user" /> {{ user.displayName }}</NuxtLink>
          <button type="button" @click="logout"><Icon name="lucide:log-out" /> Sign out</button>
        </template>
        <template v-else>
          <NuxtLink to="/login"><Icon name="lucide:log-in" /> Log in</NuxtLink>
          <NuxtLink to="/signup"><Icon name="lucide:user-plus" /> Sign up</NuxtLink>
        </template>
      </div>
    </header>

    <main class="site-main">
      <slot />
    </main>

    <footer class="site-footer">
      <div class="container footer-inner">
        <p>
          Salesforce Passport teaches Passport Seva Kendra, a public, runnable Salesforce build —
          <a href="https://github.com/imswarnil/Passport-Seva-Kendra-Salesforce" target="_blank" rel="noopener">
            fork the org on GitHub
          </a>.
        </p>
        <nav class="footer-nav">
          <NuxtLink to="/lessons">Start Here</NuxtLink>
          <NuxtLink to="/demo-org">Demo org</NuxtLink>
          <NuxtLink to="/resources">Resources</NuxtLink>
          <NuxtLink to="/guestbook">Guestbook</NuxtLink>
        </nav>
      </div>
    </footer>
  </div>
</template>

<style scoped>
.shell { min-height: 100%; display: flex; flex-direction: column; }

/* Navy chrome — the org's own HEADER_BACKGROUND_COLOR (brandingSets/
   LEXTHEMINGSalesforcePassport), not a generic surface token, so the site's
   header/footer read as the same brand as the Lightning app itself. */
.site-header {
  background: var(--brand-navy);
  position: sticky;
  top: 0;
  z-index: 10;
  box-shadow: 0 1px 0 var(--brand-on-navy-line);
}
.header-inner {
  display: flex;
  align-items: center;
  gap: 2rem;
  height: 4rem;
}
.brand {
  display: flex;
  align-items: center;
  gap: 0.6rem;
  text-decoration: none;
  color: var(--brand-on-navy);
  font-weight: 700;
}
.brand-mark {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 1.9rem;
  height: 1.9rem;
  background: var(--gold-400);
  color: var(--navy-900);
  font-size: 1.05rem;
  border-radius: 7px;
}
.brand-name { font-size: 0.95rem; }

.main-nav {
  display: flex;
  gap: 1.5rem;
  flex: 1;
}
.main-nav a {
  display: inline-flex;
  align-items: center;
  gap: 0.4rem;
  color: var(--brand-on-navy-muted);
  text-decoration: none;
  font-size: 0.92rem;
}
.main-nav a:hover,
.main-nav a.router-link-active { color: var(--brand-on-navy); }

.auth-links { display: flex; gap: 0.6rem; }
.auth-links .btn-ghost {
  color: var(--brand-on-navy);
  border-color: var(--brand-on-navy-line);
}
.auth-links .btn-ghost:hover { background: oklch(100% 0 0 / 0.08); }

.hamburger {
  display: none;
  align-items: center;
  justify-content: center;
  width: 2.25rem;
  height: 2.25rem;
  border: none;
  background: none;
  color: var(--brand-on-navy);
  font-size: 1.3rem;
  cursor: pointer;
}

.mobile-nav { display: none; }

.site-main { flex: 1; }

.site-footer {
  background: var(--brand-navy-deep);
  padding: 2rem 0;
  margin-top: 4rem;
}
.footer-inner {
  display: flex;
  justify-content: space-between;
  align-items: center;
  flex-wrap: wrap;
  gap: 1rem;
}
.footer-inner p { margin: 0; color: var(--brand-on-navy-muted); font-size: 0.88rem; }
.footer-inner a { color: var(--gold-300); }
.footer-nav { display: flex; gap: 1.25rem; }
.footer-nav a { color: var(--brand-on-navy-muted); text-decoration: none; font-size: 0.88rem; }
.footer-nav a:hover { color: var(--brand-on-navy); }

@media (max-width: 720px) {
  .main-nav, .auth-links { display: none; }
  .hamburger { display: flex; }

  .mobile-nav {
    display: flex;
    flex-direction: column;
    gap: 0.15rem;
    padding: 0.75rem 1.5rem 1.25rem;
    border-top: 1px solid var(--brand-on-navy-line);
  }
  .mobile-nav a,
  .mobile-nav button {
    display: flex;
    align-items: center;
    gap: 0.6rem;
    padding: 0.65rem 0.25rem;
    color: var(--brand-on-navy-muted);
    text-decoration: none;
    font: inherit;
    font-size: 0.95rem;
    background: none;
    border: none;
    text-align: left;
    cursor: pointer;
  }
  .mobile-nav a:hover,
  .mobile-nav a.router-link-active,
  .mobile-nav button:hover { color: var(--brand-on-navy); }
  .mobile-nav hr { border: none; border-top: 1px solid var(--brand-on-navy-line); margin: 0.4rem 0; }
}
</style>
