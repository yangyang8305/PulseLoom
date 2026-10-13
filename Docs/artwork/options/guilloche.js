// 雕版织纹 · Guilloché — an engine-turned rosette, the way a geometric lathe cuts one on a banknote
// or a watch dial: ONE lobed curve r(θ) = base + A·sin(kθ + φ) is repeated with evenly spaced phases,
// so the copies cross each other in a regular lattice of lens-shaped cells that tighten towards a
// clean centre circle. Two such lattices (8 lobes and 6 lobes) lie over each other and turn in
// opposite directions, so the moiré between them drifts very slowly. Precision comes from the
// regularity of hairlines, not from colour; light comes from the upper left (the stroke itself is
// an off-centre radial gradient), so no overlay discs are needed and dark mode stays clean.
window.OPTION = {
  name: '雕版织纹', english: 'Guilloché',
  note: '静止时两层格纹反向极慢旋转、莫尔纹缓缓流动；震动时格纹随强度向外张开、墨色加深；每次起音一圈涟漪从中心小圆扫过格纹到外缘（经过处线条短暂外鼓再回落），中心细环同时亮一下。',

  draw(p) {
    const { ctx, cx, cy, R, env, spring, hits, rot, breath, palette: P, dark, rgba, reduce, state: S } = p;
    const N = 300;                                              // samples per curve
    if (!S.cos) {                                               // one-time trig tables
      S.cos = new Float32Array(N + 1); S.sin = new Float32Array(N + 1);
      for (let j = 0; j <= N; j++) { const t = j / N * Math.PI * 2; S.cos[j] = Math.cos(t); S.sin[j] = Math.sin(t); }
    }
    const C = S.cos, Sn = S.sin, col = P.accent;
    const TAU = Math.PI * 2;

    // --- geometry (all in units of R)
    const grow = 1 + (reduce ? 0 : spring * 0.018) + (breath - 0.5) * 0.008;   // onset nudge + 10 s breath
    const open = 1 + env * 0.10;                                // vibration: the lattice opens outward
    const base = 0.53 * grow; let ampl = 0.27 * grow * open;        // rosette spans 0.26R … 0.80R
    const rCentre = R * (base - ampl) * 0.985;                  // the clean centre circle

    // --- onset ripples: a radial bulge that runs from the centre circle to the rim in 0.6 s
    const fronts = reduce ? [] : hits
      .map(h => ({ pos: 0.2 + h.age / 0.6 * 0.75, fade: Math.max(0, 1 - h.age / 0.9) * h.gain }))
      .filter(f => f.fade > 0.01);
    const bump = (rn) => { let s = 0; for (const f of fronts) { const d = (rn - f.pos) / 0.09; s += f.fade * Math.exp(-d * d); } return s; };
    const ping = fronts.reduce((m, f) => Math.max(m, f.fade), 0);  // freshest onset, for the centre ring

    // --- underlay: a faint blush disc lit from the upper left, gone before the lattice ends
    const under = dark ? P.hero2 : P.hero1;                    // in dark, hero2 keeps the centre from reading as a hole
    const g = ctx.createRadialGradient(cx - R * 0.22, cy - R * 0.26, 0, cx, cy, R * 0.86);
    g.addColorStop(0, rgba(under, dark ? 0.5 : 0.95));
    g.addColorStop(0.3, rgba(under, dark ? 0.26 : 0.75));
    g.addColorStop(0.6, rgba(under, dark ? 0.1 : 0.45));
    g.addColorStop(1, rgba(under, 0));
    ctx.fillStyle = g; ctx.beginPath(); ctx.arc(cx, cy, R * 0.86, 0, TAU); ctx.fill();

    // --- the ink: strongest near the upper-left of the centre, fading outward and to the lower right
    const ink = ctx.createRadialGradient(cx - R * 0.22, cy - R * 0.24, R * 0.06, cx, cy, R * 0.84);
    ink.addColorStop(0, rgba(col, 1));
    ink.addColorStop(0.45, rgba(col, dark ? 0.72 : 0.78));
    ink.addColorStop(1, rgba(col, dark ? 0.16 : 0.22));
    ctx.strokeStyle = ink; ctx.lineJoin = 'round';

    // one copy of the lobed curve; rotating a copy by α is the same as shifting its phase by -kα
    const curve = (k, phi) => {
      ctx.beginPath();
      for (let j = 0; j <= N; j++) {
        let rn = base + ampl * Math.sin(k * (j / N * TAU) + phi);
        if (fronts.length) rn += 0.022 * bump(rn);
        const x = cx + R * rn * C[j], y = cy + R * rn * Sn[j];
        if (j === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
      }
      ctx.stroke();
    };
    // a lattice: n evenly phased copies, the whole thing slowly rotating
    const lattice = (k, n, rotation, width, alpha) => {
      ctx.lineWidth = width;
      ctx.globalAlpha = Math.min(0.9, alpha * (1 + env * 0.3) * (dark ? 0.9 : 1));
      for (let i = 0; i < n; i++) curve(k, i * TAU / n - k * rotation);
    };
    const rotA = reduce ? 0 : rot * 0.12, rotB = reduce ? 0 : -rot * 0.09;   // ≈0.5°/s at rest
    lattice(8, 16, rotA, 0.6, 0.42);
    ampl *= 0.93;                                               // the second lattice nests just inside the first
    lattice(6, 10, rotB + 0.05, 0.5, 0.24);

    // --- centre: one hairline ring, which brightens for a moment on each onset
    ctx.globalAlpha = 1; ctx.lineWidth = 0.7;
    ctx.strokeStyle = rgba(col, (dark ? 0.55 : 0.5) + 0.35 * ping);
    ctx.beginPath(); ctx.arc(cx, cy, rCentre, 0, TAU); ctx.stroke();
    ctx.lineWidth = 0.5; ctx.strokeStyle = rgba(col, dark ? 0.22 : 0.2);   // a quieter inner chapter ring
    ctx.beginPath(); ctx.arc(cx, cy, rCentre * 0.88, 0, TAU); ctx.stroke();
    ctx.lineWidth = 0.5;                                        // the ripples themselves, leaving the ring
    for (const f of fronts) {
      ctx.strokeStyle = rgba(col, 0.3 * f.fade);
      ctx.beginPath(); ctx.arc(cx, cy, R * f.pos, 0, TAU); ctx.stroke();
    }
  },
};
