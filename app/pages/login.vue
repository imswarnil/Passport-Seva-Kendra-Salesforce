<script setup lang="ts">
const { login } = useAuth()
const router = useRouter()

const email = ref('')
const password = ref('')
const error = ref('')
const pending = ref(false)

async function onSubmit() {
  error.value = ''
  pending.value = true
  try {
    await login({ email: email.value, password: password.value })
    router.push('/dashboard')
  } catch (e: any) {
    error.value = e?.data?.statusMessage ?? 'Could not sign in.'
  } finally {
    pending.value = false
  }
}
</script>

<template>
  <div class="container auth-page">
    <h1>Sign in</h1>
    <p>Track lesson progress, comment, and submit resources.</p>

    <form class="auth-form" @submit.prevent="onSubmit">
      <label>
        Email
        <input v-model="email" type="email" required autocomplete="email">
      </label>
      <label>
        Password
        <input v-model="password" type="password" required autocomplete="current-password">
      </label>
      <p v-if="error" class="form-error">{{ error }}</p>
      <button type="submit" :disabled="pending">{{ pending ? 'Signing in…' : 'Sign in' }}</button>
    </form>

    <p>No account yet? <NuxtLink to="/signup">Sign up</NuxtLink></p>
  </div>
</template>

<style scoped>
.auth-page { max-width: 28rem; padding-block: 3rem; }
.auth-form { display: grid; gap: 1rem; margin-block: 1.5rem; }
label { display: grid; gap: 0.375rem; color: var(--fg-muted); font-size: 0.9rem; }
input {
  padding: 0.6rem 0.75rem;
  border: 1px solid var(--line-default);
  border-radius: 6px;
  background: var(--bg-surface);
  color: var(--fg-default);
  font-size: 1rem;
}
input:focus { outline: 2px solid var(--accent-ring); outline-offset: 1px; border-color: var(--accent); }
button {
  padding: 0.65rem 1rem;
  border: none;
  border-radius: 6px;
  background: var(--accent);
  color: var(--fg-on-accent);
  font-weight: 600;
  cursor: pointer;
}
button:hover:not(:disabled) { background: var(--accent-hover); }
button:disabled { opacity: 0.6; cursor: not-allowed; }
.form-error {
  color: var(--danger-fg);
  background: var(--danger-bg);
  border: 1px solid var(--danger-line);
  border-radius: 6px;
  padding: 0.5rem 0.75rem;
  font-size: 0.9rem;
}
</style>
