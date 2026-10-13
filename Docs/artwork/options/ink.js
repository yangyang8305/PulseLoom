// 墨晕 · Ink Bloom — a single drop of colour spreading in still water.
// One stain, a second wetter pass that crept past its rim toward the lower right, and a wet halo
// ahead of it toward the light — three washes of one hue, so nothing muddies. Each wash is a stack of nested organic
// outlines filled at low alpha: the softness follows the outline the way pigment thins at the edge of
// a wet stain, and the outermost layer is a hair denser (the dried rim). Light multiplies, dark adds plum.
// Every onset blooms a fresh wash from the pooled centre: fast spread, slow sink.
window.OPTION = {
  name: '墨晕', english: 'Ink Bloom',
  note: '静止时一滴色晕极慢漂移、轮廓缓缓呼吸；震动时颜色随强度沉淀变浓；每次起音从色心晕开一团新淡色，快速铺开再慢慢沉下去。',

  // ---- deterministic setup (LCG, runs once) --------------------------------------------------------
  init(state) {
    let s = 11;
    const rnd = () => (s = (s * 1664525 + 1013904223) >>> 0) / 4294967296;
    // washes: relative offset (ox, oy), radius r, colour key, density a (light), density in dark
    const spec = [
      [-0.03, -0.02, 0.52, 'hero1', 0.45, 0.12],   // the wet halo: water, not colour
      [0.00, 0.00, 0.40, 'hero3', 0.46, 0.60],     // the drop itself
      [0.06, 0.06, 0.44, 'hero3', 0.13, 0.14],     // a second, wetter pass that crept past the first rim
    ];
    state.blobs = spec.map(([ox, oy, r, key, a, ad]) => ({
      ox, oy, r, key, a, ad,
      // Lissajous drift: different periods per axis, tiny amplitude (fractions of R)
      ax: 0.025 + rnd() * 0.02, ay: 0.02 + rnd() * 0.02,
      fx: 1 / (26 + rnd() * 14), fy: 1 / (31 + rnd() * 16), ph: rnd() * 6.283,
      // outline harmonics: wavenumber, amplitude, phase, slow phase drift (rad/s). Calm, nearly round.
      h: [2, 3, 5].map(k => ({ k, amp: (k === 2 ? 0.065 : k === 3 ? 0.04 : 0.014) * (0.8 + rnd() * 0.5), ph: rnd() * 6.283, w: (rnd() - 0.5) * 0.04 })),
      // pigment pools toward lower-right (light from upper-left): inner layers slide that way
      px: 0.16 + rnd() * 0.08, py: 0.14 + rnd() * 0.08,
    }));
    state.ready = true;
  },

  // ---- colour helpers ------------------------------------------------------------------------------
  mix(a, b, t) {
    const A = parseInt(a.slice(1), 16), B = parseInt(b.slice(1), 16);
    return '#' + [16, 8, 0].map(sh => Math.round((A >> sh & 255) * (1 - t) + (B >> sh & 255) * t).toString(16).padStart(2, '0')).join('');
  },

  // ---- one organic outline: radius modulated by a few low-order sines ------------------------------
  outline(ctx, x, y, r, h, t, phase) {
    const N = 64;
    ctx.beginPath();
    for (let i = 0; i <= N; i++) {
      const th = (i / N) * 6.283;
      let m = 1;
      for (const hh of h) m += hh.amp * Math.sin(hh.k * th + hh.ph + phase + t * hh.w);
      const rr = r * m;
      i ? ctx.lineTo(x + Math.cos(th) * rr, y + Math.sin(th) * rr) : ctx.moveTo(x + Math.cos(th) * rr, y + Math.sin(th) * rr);
    }
    ctx.closePath();
  },

  // ---- one wash: nested outlines, outermost a hair denser (the dried rim), inner ones pooled -------
  // `core` is an optional second colour the layers lean toward as they pool (dark mode: a mauve glow).
  wash(ctx, rgba, x, y, r, color, core, A, b, t, rim) {
    const L = 30, la = 1 - Math.pow(1 - A, 1 / L);
    for (let i = 0; i < L; i++) {
      const u = Math.pow(i / L, 1.3), sc = 1 - 0.78 * u;     // close steps at the rim, wider inside
      const k = i === 0 ? rim : i === 1 ? 0.45 : 1;           // rim: a hairline of settled pigment, then a paler gap
      ctx.fillStyle = rgba(core ? this.mix(color, core, u * 0.8) : color, la * k);
      this.outline(ctx, x + b.px * r * u, y + b.py * r * u, r * sc, b.h, t, i * 0.05);
      ctx.fill();
    }
  },

  draw(p) {
    const { ctx, cx, cy, R, now, env, spring, hits, breath, palette, dark, rgba, reduce, state } = p;
    if (!state.ready) this.init(state);
    const t = now / 1000, drift = reduce ? 0 : 1;
    // whole mark breathes imperceptibly, swells a touch with env and the onset spring
    const scale = 1 + env * 0.05 + spring * 0.04 + drift * (breath - 0.5) * 0.012;
    // light multiplies (darker = denser). Dark adds light, but adds the deepest plum (hero2) — the most
    // chromatic colour per unit of brightness — so thin edges stay plum instead of greying; only the pooled
    // core leans toward hero3/accent and glows.
    const density = (dark ? 0.9 : 1.1) * (1 + env * 0.45);
    const rim = dark ? 1.5 : 2.6;
    const col = key => (dark ? palette.hero2 : palette[key]);
    const core = dark ? this.mix(palette.hero3, palette.accent, 0.35) : null;
    const fresh = dark ? this.mix(palette.hero3, palette.accent, 0.4) : palette.hero2;   // onset colour

    ctx.save();
    ctx.translate(cx, cy); ctx.scale(scale, scale);
    ctx.globalCompositeOperation = dark ? 'lighter' : 'multiply';

    // 1. the standing washes
    for (const b of state.blobs) {
      const a = (dark ? b.ad : b.a) * density;
      if (a <= 0) continue;
      const x = (b.ox + drift * b.ax * Math.sin(t * b.fx * 6.283 + b.ph)) * R;
      const y = (b.oy + drift * b.ay * Math.sin(t * b.fy * 6.283 + b.ph * 1.7)) * R;
      this.wash(ctx, rgba, x, y, b.r * R, col(b.key), core, Math.min(0.95, a), b, t, rim);
    }

    // 2. onset blooms: a fresh wash spreads fast from where the pigment pools, then slowly sinks away
    const drop = state.blobs[1];
    for (const h of hits) {
      const k = 1 - Math.exp(-h.age * 3.4);                   // fast spread
      const r = R * (0.14 + 0.30 * k);
      const life = Math.max(0, 1 - h.age / 1.6);
      const a = h.gain * (dark ? 0.1 : 0.30) * life * life;
      if (a < 0.004) continue;
      this.wash(ctx, rgba, R * 0.05, R * 0.04, r, fresh, null, a, drop, t + h.age * 0.6, 1);   // wet: no rim
    }
    ctx.restore();
  },
};
