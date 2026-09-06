<script setup lang="ts">
const emit = defineEmits<{ save: [dataUrl: string], cancel: [] }>()

const canvasEl = ref<HTMLCanvasElement>()
let ctx: CanvasRenderingContext2D | null = null
let drawing = false
let hasDrawn = false

const WIDTH = 360
const HEIGHT = 140

onMounted(() => {
  const canvas = canvasEl.value!
  canvas.width = WIDTH
  canvas.height = HEIGHT
  ctx = canvas.getContext('2d')
  if (!ctx) return
  ctx.fillStyle = '#ffffff'
  ctx.fillRect(0, 0, WIDTH, HEIGHT)
  ctx.lineCap = 'round'
  ctx.lineJoin = 'round'
  ctx.lineWidth = 3
  ctx.strokeStyle = '#1A2A5E'
})

function pointFromEvent(e: PointerEvent) {
  const rect = canvasEl.value!.getBoundingClientRect()
  return { x: e.clientX - rect.left, y: e.clientY - rect.top }
}

function start(e: PointerEvent) {
  if (!ctx) return
  drawing = true
  hasDrawn = true
  const p = pointFromEvent(e)
  ctx.beginPath()
  ctx.moveTo(p.x, p.y)
}
function move(e: PointerEvent) {
  if (!drawing || !ctx) return
  const p = pointFromEvent(e)
  ctx.lineTo(p.x, p.y)
  ctx.stroke()
}
function stop() { drawing = false }

function clear() {
  if (!ctx) return
  ctx.fillStyle = '#ffffff'
  ctx.fillRect(0, 0, WIDTH, HEIGHT)
  hasDrawn = false
}

function save() {
  if (!hasDrawn || !canvasEl.value) return
  emit('save', canvasEl.value.toDataURL('image/png'))
}
</script>

<template>
  <div class="doodle-pad">
    <canvas
      ref="canvasEl"
      class="doodle-canvas"
      @pointerdown="start"
      @pointermove="move"
      @pointerup="stop"
      @pointerleave="stop"
    />
    <div class="doodle-actions">
      <button type="button" class="btn btn-ghost" @click="clear"><Icon name="lucide:eraser" /> Clear</button>
      <button type="button" class="btn btn-ghost" @click="emit('cancel')">Cancel</button>
      <button type="button" class="btn btn-primary" @click="save"><Icon name="lucide:check" /> Add doodle</button>
    </div>
  </div>
</template>

<style scoped>
.doodle-pad { display: inline-flex; flex-direction: column; gap: 0.6rem; }
.doodle-canvas {
  border: 1px solid var(--line-default);
  border-radius: 8px;
  touch-action: none;
  cursor: crosshair;
  background: #fff;
}
.doodle-actions { display: flex; gap: 0.5rem; }
.doodle-actions .btn { padding: 0.4rem 0.75rem; font-size: 0.85rem; }
</style>
