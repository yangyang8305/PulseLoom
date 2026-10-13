// 雨落静水 — Still Water. A shallow stone basin of water seen from slightly above (rings are ellipses,
// ry = K·rx). Each drop spawns 2–3 concentric rings that travel outward, lose amplitude and fade; every
// ring is two hairlines (light toward the top-left light source, dark toward the bottom-right) so it reads
// as relief. Idle: a light drop every few seconds. Haptics: onset gain picks the landing spot (strong =
// centre) and the amplitude. Music: the same, plus a fine drizzle that follows env. Two petals rest on the
// surface and get nudged by passing rings.
window.OPTION = {
  name: '雨落静水', english: 'Still Water',
  note: '静止时每隔几秒落一滴轻雨；震动时起音强度决定落点与波幅；音乐时随能量再添细碎小涟漪。',

  tick(p) {
    const { dt, now, env, state } = p;
    const s = init(state);
    // quiet timer: idle rain only after 1.5 s of silence
    s.quiet = env < 0.04 ? s.quiet + dt : 0;
    if (s.quiet === 0) s.nextRain = now + 1800;
    if (s.quiet > 1.5 && now >= s.nextRain) {
      const ang = rnd(s) * Math.PI * 2, rad = 0.15 + 0.6 * Math.sqrt(rnd(s));
      spawn(s, now, Math.cos(ang) * rad, Math.sin(ang) * rad, 0.42 + 0.3 * rnd(s), 'rain');
      s.nextRain = now + 2100 + 1500 * rnd(s);
    }
    // continuous energy (music): a fine drizzle whose rate follows env
    if (env > 0.3 && rnd(s) < dt * env * 1.6 && s.drops.filter(d => d.kind === 'fine').length < 2) {
      const ang = rnd(s) * Math.PI * 2, rad = 0.15 + 0.75 * Math.sqrt(rnd(s));
      spawn(s, now, Math.cos(ang) * rad, Math.sin(ang) * rad, 0.12 + 0.1 * env, 'fine');
    }
    s.drops = s.drops.filter(d => now - d.born < d.life * 1000);
  },

  draw(p) {
    const { ctx, cx, cy, R, now, env, spring, hits, breath, palette: P, dark, rgba, reduce, state } = p;
    const s = init(state);
    const K = 0.62, rx = R * 0.96, ry = rx * K, LIP = 7;   // water ellipse and the width of the stone lip
    // light mode: highlights are the page white, shadows the deep blush; dark mode: highlights are the pale
    // accent rose (never the grey of pure ink), shadows the page black
    const lightCol = dark ? P.accent : P.surface, darkCol = dark ? P.bg : P.hero3;
    const t = now / 1000;

    // --- haptic onsets → drops (dedupe by birth time; works both live and in a single-frame render)
    if (!reduce) for (const hit of hits) {
      const born = Math.round(now - hit.age * 1000);
      if (born <= s.lastHit) continue;
      s.lastHit = born;
      const ang = hash(born) * Math.PI * 2, rad = (1 - hit.gain) * 0.8 + 0.12 * hash(born + 7);
      spawn(s, born, Math.cos(ang) * rad, Math.sin(ang) * rad, 0.45 + 0.55 * hit.gain, 'hit');
    }

    // --- stone lip: a flat ledge almost the colour of the page; only its rounded outer edge catches light
    let g;
    ellipse(ctx, cx, cy, rx + LIP, ry + LIP);
    ctx.fillStyle = rgba(P.hero2, dark ? 0.1 : 0.14); ctx.fill();
    g = diag(ctx, cx, cy, rx + LIP, ry + LIP);
    g.addColorStop(0, rgba(lightCol, dark ? 0.05 : 0.6)); g.addColorStop(0.5, rgba(darkCol, 0.03)); g.addColorStop(1, rgba(darkCol, dark ? 0.6 : 0.22));
    ctx.lineWidth = 0.7; ctx.strokeStyle = g; ctx.stroke();

    // --- water body: clip to the pool; far side (top) reflects a little sky, the middle is the deepest
    ctx.save();
    ellipse(ctx, cx, cy, rx, ry); ctx.clip();
    ctx.fillStyle = P.hero1; ctx.fillRect(cx - rx, cy - ry, rx * 2, ry * 2);
    g = ctx.createLinearGradient(0, cy - ry, 0, cy + ry);
    if (dark) { g.addColorStop(0, rgba(P.hero2, 0.62)); g.addColorStop(0.5, rgba(P.hero2, 0.2)); g.addColorStop(1, rgba(P.bg, 0.5 + env * 0.1)); }
    else { g.addColorStop(0, rgba(P.hero2, 0.3)); g.addColorStop(0.55, rgba(P.hero2, 0.62)); g.addColorStop(1, rgba(P.hero2, 0.92 + env * 0.08)); }
    ctx.fillStyle = g; ctx.fillRect(cx - rx, cy - ry, rx * 2, ry * 2);
    // depth: the basin floor shows through, a shade deeper toward the centre
    ctx.save(); ctx.translate(cx, cy + ry * 0.12); ctx.scale(1, K);
    g = ctx.createRadialGradient(0, 0, 0, 0, 0, rx);
    g.addColorStop(0, rgba(darkCol, dark ? 0.22 : 0.14)); g.addColorStop(0.55, rgba(darkCol, dark ? 0.1 : 0.06)); g.addColorStop(1, rgba(darkCol, 0));
    ctx.fillStyle = g; ctx.fillRect(-rx, -rx, rx * 2, rx * 2); ctx.restore();

    // --- sky reflection: one wide, very flat, very soft patch near the far rim, drifting on a ~10 s cycle,
    //     swelling with the breath and jolted a touch by the spring
    const lx = cx - rx * 0.22 + Math.sin(t / 2.1) * 9 + spring * 6, ly = cy - ry * 0.5 + Math.cos(t / 2.9) * 4 + spring * 3;
    const la = (dark ? 0.05 : 0.24) * (1 + env * 0.35 + breath * 0.12);
    ctx.save(); ctx.translate(lx, ly); ctx.rotate(-0.22); ctx.scale(1, 0.3);
    glow(ctx, rgba, lightCol, rx * 0.78 + breath * 6, la);
    ctx.restore();

    // --- concave cues: the lip shades the water along the far, top-left side (a soft 12 px inner shadow
    //     built from four stacked hairline-to-wide strokes); its lit inner wall shows as one line bottom-right
    for (let i = 0; i < 4; i++) {
      g = diag(ctx, cx, cy, rx, ry);
      g.addColorStop(0, rgba(darkCol, (dark ? 0.26 : 0.11) * (1 - i * 0.18))); g.addColorStop(0.42, rgba(darkCol, 0)); g.addColorStop(1, rgba(darkCol, 0));
      const wdt = 4 + i * 4;
      ellipse(ctx, cx, cy, rx + wdt / 2 - 0.5, ry + wdt / 2 - 0.5); ctx.lineWidth = wdt * 2; ctx.strokeStyle = g; ctx.stroke();
    }
    g = diag(ctx, cx, cy, rx, ry);
    g.addColorStop(0, rgba(lightCol, 0)); g.addColorStop(0.55, rgba(lightCol, 0)); g.addColorStop(1, rgba(lightCol, dark ? 0.3 : 0.9));
    ellipse(ctx, cx, cy, rx - 0.8, ry - 0.8); ctx.lineWidth = 1.2; ctx.strokeStyle = g; ctx.stroke();

    // --- ripples
    if (!reduce) {
      const V = 54, DELAY = 0.3;
      for (const d of s.drops) {
        const age = (now - d.born) / 1000, x0 = cx + d.u * rx, y0 = cy + d.v * ry;
        const fade = Math.pow(Math.max(0, 1 - age / d.life), 1.3);
        const rings = d.kind === 'fine' ? 1 : d.amp > 0.75 ? 3 : 2;
        for (let i = 0; i < rings; i++) {
          const r = R0 + V * (d.kind === 'fine' ? 0.7 : 1) * (age - i * DELAY);
          if (r <= R0) continue;
          const amp = d.amp * (1 - 0.28 * i) * fade / (1 + r / 120);
          if (amp < 0.015) continue;
          ring(ctx, rgba, x0, y0, r, r * K, amp, lightCol, darkCol, dark);
        }
        // impact: a small bead of light that sinks into the opening dimple over the first 0.3 s
        if (age < 0.32 && d.kind !== 'fine') {
          const k = 1 - age / 0.32, rr = 2 + 8 * age;
          ctx.beginPath(); ctx.ellipse(x0, y0 + 0.4, rr, rr * K, 0, 0, Math.PI * 2);
          ctx.strokeStyle = rgba(darkCol, (dark ? 0.3 : 0.26) * k * d.amp); ctx.lineWidth = 0.7; ctx.stroke();
          ctx.beginPath(); ctx.arc(x0 - 0.3, y0 - 0.5, 0.7 + d.amp * 1.0 * k, 0, Math.PI * 2);
          ctx.fillStyle = rgba(lightCol, (dark ? 0.4 : 0.7) * k * d.amp); ctx.fill();
        }
      }
    }

    // --- petals: home + slow drift + a nudge from each passing leading ring
    for (const pt of s.petals) {
      let px = cx + pt.u * rx + Math.sin(t / 3.7 + pt.ph) * 3, py = cy + pt.v * ry + Math.cos(t / 4.3 + pt.ph) * 1.6;
      let rot = pt.rot + Math.sin(t / 5.1 + pt.ph) * 0.05;
      if (!reduce) for (const d of s.drops) {
        const age = (now - d.born) / 1000, dx = px - (cx + d.u * rx), dy = (py - (cy + d.v * ry)) / K;
        const dist = Math.hypot(dx, dy) || 1, r = R0 + 54 * age;
        const push = d.amp * 5 * Math.exp(-Math.pow((dist - r) / 9, 2)) * Math.max(0, 1 - age / d.life);
        px += dx / dist * push; py += dy / dist * push * K; rot += push * 0.03 * Math.sign(dx);
      }
      petal(ctx, rgba, px, py, rot, pt.len, P, dark, lightCol, darkCol);
    }
    ctx.restore(); // water clip
  },
};

// ---------- helpers ----------
const R0 = 4;
function init(s) {
  if (s.drops) return s;
  s.seed = 7; s.drops = []; s.quiet = 0; s.nextRain = 1200; s.lastHit = -1;
  s.petals = [
    { u: 0.4, v: 0.36, rot: -0.55, len: 24, ph: 0 },
    { u: -0.46, v: 0.16, rot: 0.75, len: 20, ph: 2.1 },
  ];
  return s;
}
function rnd(s) { s.seed = (s.seed * 1664525 + 1013904223) >>> 0; return s.seed / 4294967296; }
function hash(n) { let x = (n * 2654435761) >>> 0; x ^= x >>> 15; x = (x * 2246822519) >>> 0; x ^= x >>> 13; return (x >>> 0) / 4294967296; }
function spawn(s, born, u, v, amp, kind) {
  const life = kind === 'fine' ? 1.3 : kind === 'rain' ? 3.4 : 1.9 + 1.6 * amp;
  s.drops.push({ born, u, v, amp, kind, life });
  if (s.drops.length > 5) s.drops.shift(); // keep the surface calm
}
function glow(ctx, rgba, col, r, a) {
  const g = ctx.createRadialGradient(0, 0, 0, 0, 0, r);
  g.addColorStop(0, rgba(col, a)); g.addColorStop(0.45, rgba(col, a * 0.4)); g.addColorStop(1, rgba(col, 0));
  ctx.fillStyle = g; ctx.beginPath(); ctx.arc(0, 0, r, 0, Math.PI * 2); ctx.fill();
}
function ellipse(ctx, x, y, rx, ry) { ctx.beginPath(); ctx.ellipse(x, y, rx, ry, 0, 0, Math.PI * 2); }
// gradient along the light direction (top-left → bottom-right) across an ellipse
function diag(ctx, x, y, rx, ry) { return ctx.createLinearGradient(x - rx, y - ry, x + rx, y + ry); }
// One ripple ring = light hairline offset toward the light, dark hairline offset away; each alpha-graded
// along the light direction so the crest looks embossed instead of outlined.
function ring(ctx, rgba, x, y, rx, ry, amp, lightCol, darkCol, dark) {
  const o = 0.6, aL = Math.min(1, amp * (dark ? 0.5 : 1.2)), aD = amp * (dark ? 0.8 : 0.7);
  let g = diag(ctx, x, y, rx, ry);
  g.addColorStop(0, rgba(lightCol, aL)); g.addColorStop(0.5, rgba(lightCol, aL * 0.3)); g.addColorStop(1, rgba(lightCol, 0));
  ctx.beginPath(); ctx.ellipse(x - o * 0.6, y - o, rx, ry, 0, 0, Math.PI * 2);
  ctx.lineWidth = 0.85; ctx.strokeStyle = g; ctx.stroke();
  g = diag(ctx, x, y, rx, ry);
  g.addColorStop(0, rgba(darkCol, 0)); g.addColorStop(0.5, rgba(darkCol, aD * 0.3)); g.addColorStop(1, rgba(darkCol, aD));
  ctx.beginPath(); ctx.ellipse(x + o * 0.6, y + o, rx, ry, 0, 0, Math.PI * 2);
  ctx.lineWidth = 0.8; ctx.strokeStyle = g; ctx.stroke();
}
// A cherry petal (rounded base, notched tip) lying flat on the water: a faint reflection right beneath it
// (no cast-shadow offset — it floats on the surface, not above it), a lit top-left half and a hairline edge.
function petal(ctx, rgba, x, y, rot, len, P, dark, lightCol, darkCol) {
  const L = len / 2, W = len * 0.3;
  const shape = () => {
    ctx.beginPath(); ctx.moveTo(-L, 0);
    ctx.bezierCurveTo(-L * 0.6, -W * 1.15, L * 0.55, -W, L, -W * 0.28);
    ctx.quadraticCurveTo(L * 0.72, 0, L, W * 0.28);
    ctx.bezierCurveTo(L * 0.55, W, -L * 0.6, W * 1.15, -L, 0); ctx.closePath();
  };
  ctx.save(); ctx.translate(x + 0.6, y + 1.4); ctx.rotate(rot); ctx.scale(1.04, 0.9);
  shape(); ctx.fillStyle = rgba(darkCol, dark ? 0.35 : 0.12); ctx.fill(); // reflection on the water
  ctx.restore();
  ctx.save(); ctx.translate(x, y); ctx.rotate(rot); ctx.scale(1, 0.86);
  shape(); ctx.fillStyle = dark ? rgba(P.hero3, 0.85) : rgba(P.hero2, 0.95); ctx.fill();
  shape(); ctx.fillStyle = rgba(P.hero3, dark ? 0 : 0.22); ctx.fill();
  // lit half: the side facing the light source, faded toward the midrib
  ctx.save(); ctx.clip();
  const g = ctx.createLinearGradient(0, -W, 0, W * 0.4);
  g.addColorStop(0, rgba(lightCol, dark ? 0.35 : 0.6)); g.addColorStop(1, rgba(lightCol, 0));
  ctx.fillStyle = g; ctx.fillRect(-L, -W * 1.2, 2 * L, 2.4 * W); ctx.restore();
  shape(); ctx.lineWidth = 0.55; ctx.strokeStyle = rgba(P.accent, dark ? 0.5 : 0.35); ctx.stroke();
  ctx.beginPath(); ctx.moveTo(-L * 0.85, 0); ctx.quadraticCurveTo(0, -W * 0.15, L * 0.6, 0);
  ctx.lineWidth = 0.5; ctx.strokeStyle = rgba(P.accent, dark ? 0.3 : 0.22); ctx.stroke();
  ctx.restore();
}
