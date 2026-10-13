// 莲池 — Lotus Pond. A half-closed lotus seen from above: two rings of six plump, stroke-less petals, each
// shaded by one gradient along its length (deep base → pale tip) and one across it (lit side toward the
// top-left light), with a faint midrib. A small seed pod sits in the heart. The flower floats on water that
// is only implied: a soft pool of tint, a light patch, two or three very faint elliptical ripples and a pair
// of small lily pads far off. Idle: the flower turns once in ~5 min, ripples spread at ~1 px/s. Haptics:
// petals open a few degrees with env, the light patch brightens. Each onset sends one ripple out from the
// flower's base.
window.OPTION = {
  name: '莲池', english: 'Lotus Pond',
  note: '静止时莲花几分钟转一圈、水纹以每秒一像素的速度外扩；震动时花瓣随强度张开几度、水面光斑变亮；每次起音从花底荡出一圈水纹。',

  draw(p) {
    const { ctx, w, h, cx, cy, R, now, env, spring, hits, rot, breath, palette: P, dark, rgba, reduce } = p;
    const t = now / 1000, K = 0.68;                      // K: foreshortening of the water surface (ry / rx)
    const lightCol = dark ? P.ink : P.surface, darkCol = dark ? P.bg : P.hero3;
    const open = reduce ? 0 : env, br = reduce ? 0.5 : breath;
    const theta = reduce ? -0.4 : rot * 0.25 - 0.4;      // flower rotation: ~5 min per turn when idle
    const LIGHT = -2.3;                                  // light source direction (top-left), world angle
    let g;

    // --- the pond: a soft pool of tint around the flower, fading into the page before it reaches the edges
    ctx.save(); ctx.translate(cx, cy + 10); ctx.scale(1, 0.82);
    g = ctx.createRadialGradient(0, 0, 0, 0, 0, R * 1.25);
    g.addColorStop(0, rgba(P.hero1, dark ? 0.9 : 0.62)); g.addColorStop(0.55, rgba(P.hero1, dark ? 0.55 : 0.36)); g.addColorStop(1, rgba(P.hero1, 0));
    ctx.fillStyle = g; ctx.fillRect(-w, -h, 2 * w, 2 * h); ctx.restore();

    // --- light patch on the water (top-left, along the light diagonal); brightens with env, breathes slowly
    ctx.save(); ctx.translate(cx - R * 0.58 + br * 4, cy - R * 0.36 + br * 2); ctx.rotate(-0.4); ctx.scale(1, 0.55);
    glow(ctx, rgba, lightCol, R * 0.8 + br * 8, (dark ? 0.07 : 0.5) * (1 + env * 0.6));
    glow(ctx, rgba, lightCol, R * 0.38, (dark ? 0.07 : 0.45) * (1 + env * 0.6));
    ctx.restore();

    // --- idle ripples: three rings spreading so slowly they read as still, fading in at birth and out at the rim
    if (!reduce) for (let i = 0; i < 3; i++) {
      const ph = ((t / 80) + i / 3) % 1, rx = R * (0.84 + ph * 0.32);
      ring(ctx, rgba, cx, cy + 4, rx, rx * K, Math.sin(ph * Math.PI) * (dark ? 0.26 : 0.24), lightCol, darkCol, dark);
    }

    // --- lily pads, far from the flower
    pad(ctx, rgba, P, dark, cx + R * 0.95 + Math.sin(t / 5.3) * 2, cy - R * 0.62 + Math.cos(t / 6.1) * 1.2, R * 0.17, K, 2.6, lightCol, darkCol);
    pad(ctx, rgba, P, dark, cx - R * 0.98 + Math.sin(t / 4.7 + 2) * 2, cy + R * 0.46 + Math.cos(t / 5.9 + 1) * 1.2, R * 0.12, K, 0.35, lightCol, darkCol);

    // --- onset ripples: one ring per hit, born under the petal tips and travelling outward
    if (!reduce) for (const hit of hits) {
      const r = R * 0.74 + 70 * hit.age;
      const amp = hit.gain * Math.pow(Math.max(0, 1 - hit.age / 1.6), 1.4) * (dark ? 0.7 : 0.55) / (1 + (r - R * 0.74) / 160);
      if (amp > 0.01) ring(ctx, rgba, cx, cy + 4, r, r * K, amp, lightCol, darkCol, dark);
      if (hit.gain > 0.7 && hit.age > 0.2) {              // a strong onset leaves a second, weaker ring behind
        const r2 = R * 0.74 + 70 * (hit.age - 0.2);
        ring(ctx, rgba, cx, cy + 4, r2, r2 * K, amp * 0.45, lightCol, darkCol, dark);
      }
    }

    // --- contact shadow on the water, offset away from the light
    ctx.save(); ctx.translate(cx + 7, cy + 11); ctx.scale(1, 0.9);
    glow(ctx, rgba, darkCol, R * 0.86, dark ? 0.5 : 0.2);
    ctx.restore();

    // --- the flower
    const sc = 1 + (reduce ? 0 : spring * 0.02);
    ctx.save(); ctx.translate(cx, cy); ctx.scale(sc, sc * 0.92); ctx.rotate(theta);
    const la = LIGHT - theta;                                 // light direction in the flower's frame
    const off = [3 * Math.cos(theta) + 4 * Math.sin(theta), -3 * Math.sin(theta) + 4 * Math.cos(theta)]; // shadow offset, world (3,4)
    const outer = { n: 6, phase: 0, L: R * (0.7 + open * 0.04), W: R * (0.3 + open * 0.03), b: R * (0.1 + open * 0.02) };
    const inner = { n: 6, phase: Math.PI / 6, L: R * (0.48 + open * 0.03), W: R * (0.25 + open * 0.02), b: R * (0.05 + open * 0.01) };
    layer(ctx, rgba, P, dark, outer, la, lightCol, darkCol, off, dark ? 0.35 : 0.12);
    // ambient shade in the heart of the flower, under the inner petals
    glow(ctx, rgba, darkCol, R * 0.46, dark ? 0.45 : 0.22);
    layer(ctx, rgba, P, dark, inner, la, lightCol, darkCol, off, dark ? 0.4 : 0.14);
    pod(ctx, rgba, P, dark, R * 0.135, la, lightCol, darkCol);
    ctx.restore();
  },
};

// ---------- helpers ----------
function glow(ctx, rgba, col, r, a) {
  const g = ctx.createRadialGradient(0, 0, 0, 0, 0, r);
  g.addColorStop(0, rgba(col, a)); g.addColorStop(0.5, rgba(col, a * 0.35)); g.addColorStop(1, rgba(col, 0));
  ctx.fillStyle = g; ctx.beginPath(); ctx.arc(0, 0, r, 0, Math.PI * 2); ctx.fill();
}
// blend two palette colours (t = 0 → a, 1 → b)
function mix(a, b, t) { const A = parseInt(a.slice(1), 16), B = parseInt(b.slice(1), 16), c = s => Math.round(((A >> s) & 255) * (1 - t) + ((B >> s) & 255) * t); return `rgb(${c(16)},${c(8)},${c(0)})`; }
function diag(ctx, x, y, rx, ry) { return ctx.createLinearGradient(x - rx, y - ry, x + rx, y + ry); }
// One ripple = a light hairline offset toward the light and a dark hairline offset away, each alpha-graded
// along the light direction, so the crest reads as relief rather than an outline.
function ring(ctx, rgba, x, y, rx, ry, amp, lightCol, darkCol, dark) {
  const o = 0.6, aL = Math.min(1, amp * (dark ? 0.6 : 1.2)), aD = amp * (dark ? 0.8 : 0.72);
  let g = diag(ctx, x, y, rx, ry);
  g.addColorStop(0, rgba(lightCol, aL)); g.addColorStop(0.5, rgba(lightCol, aL * 0.3)); g.addColorStop(1, rgba(lightCol, 0));
  ctx.beginPath(); ctx.ellipse(x - o * 0.6, y - o, rx, ry, 0, 0, Math.PI * 2); ctx.lineWidth = 0.85; ctx.strokeStyle = g; ctx.stroke();
  g = diag(ctx, x, y, rx, ry);
  g.addColorStop(0, rgba(darkCol, 0)); g.addColorStop(0.5, rgba(darkCol, aD * 0.3)); g.addColorStop(1, rgba(darkCol, aD));
  ctx.beginPath(); ctx.ellipse(x + o * 0.6, y + o, rx, ry, 0, 0, Math.PI * 2); ctx.lineWidth = 0.8; ctx.strokeStyle = g; ctx.stroke();
}
// Petal outline in its own frame: base at the origin, tip at (0,-L), half-width W, slightly pointed tip.
function petalPath(ctx, L, W) {
  ctx.beginPath(); ctx.moveTo(0, 0);
  ctx.bezierCurveTo(-W * 0.85, -L * 0.05, -W * 1.1, -L * 0.45, -W * 0.7, -L * 0.8);   // full flank up to the shoulder
  ctx.bezierCurveTo(-W * 0.48, -L * 0.93, -W * 0.22, -L * 0.96, 0, -L);              // soft point
  ctx.bezierCurveTo(W * 0.22, -L * 0.96, W * 0.48, -L * 0.93, W * 0.7, -L * 0.8);
  ctx.bezierCurveTo(W * 1.1, -L * 0.45, W * 0.85, -L * 0.05, 0, 0); ctx.closePath();
}
// One ring of petals. Drawn from the petal facing away from the light to the one facing it, so every petal
// overlaps a darker neighbour. Shadow pass first (two soft-edged silhouettes), then each petal: length
// gradient, lateral light/shade, midrib.
function layer(ctx, rgba, P, dark, S, la, lightCol, darkCol, off, shadowA) {
  const { n, phase, L, W, b } = S;
  const ang = i => phase + i * Math.PI * 2 / n;
  const order = [...Array(n).keys()].sort((i, j) => Math.cos(ang(i) - la) - Math.cos(ang(j) - la));
  const place = (i, ox, oy, s) => { ctx.save(); const a = ang(i); ctx.translate(ox + Math.cos(a) * b, oy + Math.sin(a) * b); ctx.rotate(a + Math.PI / 2); ctx.scale(s, s); };
  for (const [k, al] of [[1, shadowA * 0.45], [1.03, shadowA * 0.3], [1.06, shadowA * 0.15]]) for (const i of order) {
    place(i, off[0] * k, off[1] * k, k); petalPath(ctx, L, W); ctx.fillStyle = rgba(darkCol, al); ctx.fill(); ctx.restore();
  }
  for (const i of order) {
    const a = ang(i), facing = Math.cos(a - la), lx = Math.sin(la - a);   // lx: lateral light component in petal frame
    place(i, 0, 0, 1);
    petalPath(ctx, L, W);
    let g = ctx.createLinearGradient(0, 0, 0, -L);
    if (dark) { g.addColorStop(0, P.hero2); g.addColorStop(0.5, P.hero3); g.addColorStop(1, mix(P.hero3, P.accent, 0.72)); }
    else { g.addColorStop(0, P.hero3); g.addColorStop(0.45, P.hero2); g.addColorStop(1, mix(P.hero2, P.hero1, 0.6)); }
    ctx.fillStyle = g; ctx.fill();
    ctx.save(); ctx.clip();
    // across the petal: the side toward the light picks up a sheen, the other side a shade
    const s = lx < 0 ? 1 : -1, m = Math.abs(lx);
    g = ctx.createLinearGradient(-W * s, 0, W * s, 0);
    g.addColorStop(0, rgba(lightCol, (dark ? 0.14 : 0.32) * m)); g.addColorStop(0.5, rgba(lightCol, 0));
    g.addColorStop(0.55, rgba(darkCol, 0)); g.addColorStop(1, rgba(darkCol, (dark ? 0.26 : 0.14) * m));
    ctx.fillStyle = g; ctx.fillRect(-W * 1.1, -L, W * 2.2, L);
    // along the petal: tips toward the light brighten, tips away from it fall into shade
    g = ctx.createLinearGradient(0, -L * 0.3, 0, -L);
    if (facing > 0) { g.addColorStop(0, rgba(lightCol, 0)); g.addColorStop(1, rgba(lightCol, (dark ? 0.12 : 0.28) * facing)); }
    else { g.addColorStop(0, rgba(darkCol, 0)); g.addColorStop(1, rgba(darkCol, (dark ? 0.22 : 0.12) * -facing)); }
    ctx.fillStyle = g; ctx.fillRect(-W * 1.1, -L, W * 2.2, L);
    // midrib: one faint hairline, fading before it reaches the tip
    g = ctx.createLinearGradient(0, -L * 0.1, 0, -L * 0.9);
    g.addColorStop(0, rgba(darkCol, dark ? 0.22 : 0.16)); g.addColorStop(1, rgba(darkCol, 0));
    ctx.beginPath(); ctx.moveTo(0, -L * 0.08); ctx.lineTo(0, -L * 0.9); ctx.lineWidth = 0.6; ctx.strokeStyle = g; ctx.stroke();
    ctx.restore(); ctx.restore();
  }
}
// Seed pod: a small dome lit from the top-left, with a hex array of seed holes (1 + 6 + 12).
function pod(ctx, rgba, P, dark, r, la, lightCol, darkCol) {
  glow(ctx, rgba, darkCol, r * 1.8, dark ? 0.5 : 0.28);           // contact shade onto the inner petals
  let g = ctx.createRadialGradient(-r * 0.4, -r * 0.4, 0, 0, 0, r);
  if (dark) { g.addColorStop(0, P.hero3); g.addColorStop(0.6, P.hero2); g.addColorStop(1, P.hero1); }
  else { g.addColorStop(0, mix(P.hero1, P.hero2, 0.4)); g.addColorStop(0.6, P.hero2); g.addColorStop(1, P.hero3); }
  ctx.beginPath(); ctx.arc(0, 0, r, 0, Math.PI * 2); ctx.fillStyle = g; ctx.fill();
  g = diag(ctx, 0, 0, r, r);                                       // rim: lit edge toward the light, dark edge away
  g.addColorStop(0, rgba(lightCol, dark ? 0.35 : 0.9)); g.addColorStop(0.5, rgba(lightCol, 0)); g.addColorStop(1, rgba(darkCol, dark ? 0.6 : 0.3));
  ctx.beginPath(); ctx.arc(0, 0, r - 0.4, 0, Math.PI * 2); ctx.lineWidth = 0.7; ctx.strokeStyle = g; ctx.stroke();
  const dots = [[0, 0]];
  for (let i = 0; i < 6; i++) dots.push([Math.cos(i * Math.PI / 3) * r * 0.42, Math.sin(i * Math.PI / 3) * r * 0.42]);
  for (let i = 0; i < 12; i++) dots.push([Math.cos(i * Math.PI / 6 + Math.PI / 12) * r * 0.76, Math.sin(i * Math.PI / 6 + Math.PI / 12) * r * 0.76]);
  const d = r * 0.085;
  for (const [x, y] of dots) {
    ctx.beginPath(); ctx.arc(x, y, d, 0, Math.PI * 2); ctx.fillStyle = rgba(darkCol, dark ? 0.7 : 0.4); ctx.fill();
    ctx.beginPath(); ctx.arc(x + 0.3, y + 0.3, d, 0.1, Math.PI * 0.6); ctx.lineWidth = 0.6; ctx.strokeStyle = rgba(lightCol, dark ? 0.3 : 0.7); ctx.stroke();
  }
}
// A small lily pad lying flat: a notched disc with faint radial veins, a lit top-left edge and a soft shadow.
function pad(ctx, rgba, P, dark, x, y, r, K, notch, lightCol, darkCol) {
  const half = 0.2;                                               // half-angle of the narrow V notch
  const shape = () => { ctx.beginPath(); ctx.arc(0, 0, r, notch + half, notch - half + Math.PI * 2); ctx.lineTo(Math.cos(notch) * r * 0.08, Math.sin(notch) * r * 0.08); ctx.closePath(); };
  ctx.save(); ctx.translate(x + 1.5, y + 2.5); ctx.scale(1, K); shape(); ctx.fillStyle = rgba(darkCol, dark ? 0.3 : 0.08); ctx.fill(); ctx.restore();
  ctx.save(); ctx.translate(x, y); ctx.scale(1, K);
  let g = ctx.createRadialGradient(-r * 0.3, -r * 0.3, 0, 0, 0, r);
  g.addColorStop(0, rgba(dark ? P.hero3 : P.hero2, dark ? 0.5 : 0.4)); g.addColorStop(1, rgba(dark ? P.hero2 : P.hero3, dark ? 0.7 : 0.3));
  shape(); ctx.fillStyle = g; ctx.fill();
  ctx.save(); ctx.clip();
  g = ctx.createRadialGradient(0, 0, 0, 0, 0, r);                   // veins fade out at the centre and at the rim
  g.addColorStop(0, rgba(darkCol, 0)); g.addColorStop(0.45, rgba(darkCol, dark ? 0.28 : 0.13)); g.addColorStop(1, rgba(darkCol, 0));
  ctx.strokeStyle = g; ctx.lineWidth = 0.5; ctx.beginPath();
  for (let i = 0; i < 9; i++) {
    const a = notch + half + (i + 0.5) * (Math.PI * 2 - 2 * half) / 9;
    ctx.moveTo(Math.cos(a) * r * 0.1, Math.sin(a) * r * 0.1); ctx.lineTo(Math.cos(a) * r, Math.sin(a) * r);
  }
  ctx.stroke();
  g = diag(ctx, 0, 0, r, r);
  g.addColorStop(0, rgba(lightCol, dark ? 0.18 : 0.4)); g.addColorStop(0.5, rgba(lightCol, 0)); g.addColorStop(1, rgba(darkCol, dark ? 0.35 : 0.12));
  shape(); ctx.fillStyle = g; ctx.fill();
  ctx.restore(); ctx.restore();
}
