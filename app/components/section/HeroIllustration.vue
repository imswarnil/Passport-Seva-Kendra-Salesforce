<script setup lang="ts">
// A small, self-contained animated SVG — no icon library, no image asset.
// The scene: a Passport_Application__c record card moving through its
// Status__c stages while a stamp comes down on "Granted" and three related
// objects orbit it, each pulsing on its own delay. Purely decorative, but
// every label on it is real (the actual field/object names), not filler.
</script>

<template>
  <div class="hero-illustration" aria-hidden="true">
    <svg viewBox="0 0 420 360" width="100%" height="100%">
      <!-- orbit rings -->
      <circle cx="210" cy="180" r="150" class="orbit-ring" />
      <circle cx="210" cy="180" r="110" class="orbit-ring orbit-ring-inner" />

      <!-- orbiting related-object nodes -->
      <g class="orbit orbit-slow">
        <g transform="translate(210 30)">
          <circle r="20" class="node-circle node-citizen" />
          <text class="node-icon" y="6">👤</text>
        </g>
      </g>
      <g class="orbit orbit-medium">
        <g transform="translate(360 250)">
          <circle r="18" class="node-circle node-payment" />
          <text class="node-icon" y="5">₹</text>
        </g>
      </g>
      <g class="orbit orbit-fast">
        <g transform="translate(70 260)">
          <circle r="16" class="node-circle node-office" />
          <text class="node-icon" y="5">🏢</text>
        </g>
      </g>

      <!-- the record card -->
      <g class="record-card">
        <rect x="90" y="120" width="240" height="130" rx="12" class="card-bg" />
        <rect x="90" y="120" width="240" height="34" rx="12" class="card-header" />
        <rect x="90" y="142" width="240" height="12" class="card-header" />
        <text x="106" y="142" class="card-title">Passport_Application__c</text>
        <text x="106" y="180" class="card-field-label">ARN</text>
        <text x="106" y="196" class="card-field-value">PSK-2026-04471</text>
        <text x="106" y="220" class="card-field-label">Status__c</text>
        <rect x="106" y="228" width="86" height="18" rx="9" class="status-pill" />
        <text x="149" y="241" class="status-pill-text">Granting</text>
      </g>

      <!-- the stamp -->
      <g class="stamp">
        <circle cx="300" cy="150" r="26" class="stamp-circle" />
        <text x="300" y="156" class="stamp-text">✓</text>
      </g>
    </svg>
  </div>
</template>

<style scoped>
.hero-illustration { width: 100%; max-width: 26rem; margin-inline: auto; }

.orbit-ring {
  fill: none;
  stroke: var(--line-subtle);
  stroke-width: 1;
  stroke-dasharray: 2 6;
}
.orbit-ring-inner { stroke: var(--line-default); }

.orbit { transform-origin: 210px 180px; }
.orbit-slow { animation: spin 22s linear infinite; }
.orbit-medium { animation: spin 16s linear infinite reverse; }
.orbit-fast { animation: spin 12s linear infinite; }

.node-circle { fill: var(--bg-surface); stroke: var(--line-default); stroke-width: 1.5; }
.node-citizen { stroke: var(--info-line); }
.node-payment { stroke: var(--success-line); }
.node-office { stroke: var(--warning-line); }
.node-icon { text-anchor: middle; font-size: 16px; }

.card-bg { fill: var(--bg-surface); stroke: var(--line-default); }
.card-header { fill: var(--brand-navy, var(--bg-muted)); }
.card-title { fill: var(--brand-on-navy, var(--fg-on-accent)); font: 600 11px ui-monospace, monospace; }
.card-field-label { fill: var(--fg-faint); font: 600 9px ui-sans-serif, sans-serif; letter-spacing: 0.04em; text-transform: uppercase; }
.card-field-value { fill: var(--fg-default); font: 600 13px ui-monospace, monospace; }
.status-pill { fill: var(--accent); }
.status-pill-text { fill: var(--navy-900, var(--fg-on-accent)); font: 700 11px ui-sans-serif, sans-serif; }

.record-card { animation: float 5s ease-in-out infinite; }

.stamp { transform-origin: 300px 150px; animation: stamp 3.5s ease-in-out infinite; }
.stamp-circle { fill: var(--gold-400); }
.stamp-text { text-anchor: middle; fill: var(--navy-900); font: 700 22px ui-sans-serif, sans-serif; }

@keyframes spin {
  from { transform: rotate(0deg); }
  to { transform: rotate(360deg); }
}
@keyframes float {
  0%, 100% { transform: translateY(0); }
  50% { transform: translateY(-6px); }
}
@keyframes stamp {
  0%, 20% { transform: translateY(-14px) rotate(-8deg) scale(0.9); opacity: 0.7; }
  30% { transform: translateY(6px) rotate(0deg) scale(1.05); opacity: 1; }
  40%, 80% { transform: translateY(0) rotate(0deg) scale(1); opacity: 1; }
  100% { transform: translateY(-14px) rotate(-8deg) scale(0.9); opacity: 0.7; }
}

@media (prefers-reduced-motion: reduce) {
  .orbit, .record-card, .stamp { animation: none; }
}
</style>
