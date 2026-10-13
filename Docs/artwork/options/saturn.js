// 土星与环系 — a single Saturn with a complete ring system. Canvas 2D, deterministic.
// Geometry: the ring plane is drawn in a "plane space" (translate → rotate φ → scale(1,k)),
// so strokes are foreshortened like a real tilted disc. Light comes from left / front / north,
// so the globe's shadow falls on the far ring to the right, and the rings shade the southern hemisphere.
(function () {
  const TAU = Math.PI * 2;
  const easeOut = t => 1 - Math.pow(1 - t, 3);
  const smooth = (a, b, x) => { const t = Math.min(1, Math.max(0, (x - a) / (b - a))); return t * t * (3 - 2 * t); };

  // Radial structure, r in planet radii: C ring (faint), B ring (bright, wide), Cassini division,
  // A ring with the Encke gap. Returns body (soft fill) and grain (fine striation) alphas.
  function ringProfile(r) {
    const g0 = 0.5 + 0.5 * (0.6 * Math.sin(r * 23 + 0.4) + 0.4 * Math.sin(r * 47 + 2.2));          // slow density
    const g1 = 0.5 + 0.5 * (0.55 * Math.sin(r * 61) + 0.3 * Math.sin(r * 147 + 1.3) + 0.15 * Math.sin(r * 331 + 2.1)); // fine grain
    const gap = (at, wd, depth) => 1 - depth * Math.exp(-Math.pow((r - at) / wd, 2));              // narrow ringlet gap
    if (r < 1.50) return { body: (0.10 + 0.08 * g0) * smooth(1.20, 1.30, r), zone: 0, grain: 0.3 * g1 };
    if (r < 1.96) { const e = smooth(1.50, 1.57, r) * (1 - 0.3 * smooth(1.92, 1.96, r)) * gap(1.64, 0.007, 0.6) * gap(1.81, 0.006, 0.5); return { body: (0.45 + 0.30 * g0) * e, zone: 1, grain: g1 * e }; }
    if (r < 2.03) return { body: 0.08, zone: 0, grain: 0.15 * g1 };
    if (r < 2.28) { const e = gap(2.21, 0.012, 0.85) * gap(2.10, 0.006, 0.5) * (1 - 0.5 * smooth(2.24, 2.28, r)); return { body: (0.32 + 0.25 * g0) * e, zone: 1, grain: 0.7 * g1 * e }; }
    return { body: 0, zone: 0, grain: 0 };
  }

  // Deterministic one-time init: ring line table, dust grains, background stars (fixed-seed LCG).
  function init(state) {
    if (state.saturn) return state.saturn;
    let seed = 20261009;
    const rnd = () => (seed = (seed * 1664525 + 1013904223) % 4294967296) / 4294967296;
    const lines = [];
    for (let i = 0; i < 104; i++) { const r = 1.20 + i * 0.0106; lines.push({ r, ...ringProfile(r) }); }
    const dust = [];
    for (let i = 0; i < 120; i++) {
      const u = rnd();
      const r = u < 0.16 ? 1.24 + rnd() * 0.25 : u < 0.70 ? 1.56 + rnd() * 0.38 : u < 0.95 ? 2.04 + rnd() * 0.23 : 2.33 + rnd() * 0.05;
      dust.push({ r, a: rnd() * TAU, s: 0.3 + rnd() * 0.45, al: 0.35 + rnd() * 0.65 });
    }
    const stars = [];
    while (stars.length < 14) {
      const x = 0.06 + rnd() * 0.88, y = 0.06 + rnd() * 0.88, dx = (x - 0.5) / 0.47, dy = (y - 0.46) / 0.27;
      if (dx * dx + dy * dy < 1) continue;
      stars.push({ x, y, s: 0.55 + rnd() * 0.7, al: 0.35 + rnd() * 0.65, ph: rnd() * TAU });
    }
    state.saturn = { lines, dust, stars, t: 0 };
    return state.saturn;
  }

  // Latitude bands on the globe: [lat0, lat1, alpha, lit?]. Very faint, alternating.
  const BANDS = [[-0.10, 0.08, 0.07, 1], [0.16, 0.30, 0.06, 0], [0.36, 0.42, 0.06, 1], [0.50, 0.63, 0.07, 0],
    [0.72, 0.80, 0.05, 0], [0.92, 1.05, 0.06, 0], [-0.20, -0.32, 0.06, 0], [-0.40, -0.46, 0.05, 1]];

  window.OPTION = {
    name: '环宇', english: 'Saturn', note: '静止时尘粒极慢绕行、环面十秒级微进动；震动时环的亮度与宽度随强度呼吸、行星光晕变亮；每次起音一粒亮点沿 B 环前缘从左向右滑过淡去。',

    tick(p) {
      const S = init(p.state);
      S.t += p.dt * (1 + p.env * 0.8); // dust orbital clock, faster while playing
    },

    draw(p) {
      const { ctx, w, h, cx, cy, R, now, env, spring, hits, breath, palette: P, dark, rgba, reduce } = p;
      const S = init(p.state);
      const Rp = R * 0.42;                                           // planet radius
      const mot = reduce ? 0 : 1;
      const phi = -0.28 + mot * 0.02 * Math.sin(TAU * now / 12000);   // ring plane rotation (slow precession)
      const k = 0.33 + mot * 0.012 * Math.sin(TAU * now / 9000 + 1);  // ring tilt (minor / major)
      const cp = Math.cos(phi), sp = Math.sin(phi);
      const rs = 1 + env * 0.03 + spring * 0.02;                      // rings widen with intensity
      const lift = 1 + env * 0.35;                                    // rings brighten with intensity
      const toScreen = (r, th) => { const x = r * Rp * Math.cos(th), y = r * Rp * Math.sin(th) * k; return [cx + x * cp - y * sp, cy + x * sp + y * cp]; };
      const planeSpace = () => { ctx.translate(cx, cy); ctx.rotate(phi); ctx.scale(1, k); };

      // colours, only from the palette. In light mode hero1 is the lightest, in dark mode hero3 is.
      const lit = dark ? P.hero3 : P.hero1, mid = P.hero2, dim = dark ? P.hero1 : P.hero3;
      const shade = dark ? P.bg : P.accent;
      const bodyCol = [dark ? P.hero2 : P.hero3, dark ? P.hero3 : P.hero2];   // by zone: faint / bright
      const grainCol = P.accent, bodyMul = (dark ? 0.85 : 0.82) * lift, grainMul = (dark ? 0.55 : 0.4) * lift;
      const haloC = dark ? P.hero3 : P.hero2, starC = dark ? P.ink : P.accent, coreC = dark ? P.ink : P.hero1;

      // --- stars ------------------------------------------------------------
      for (const s of S.stars) {
        const tw = 0.7 + 0.3 * Math.sin(now / 1400 + s.ph);
        ctx.fillStyle = rgba(starC, s.al * tw * (dark ? 0.45 : 0.3));
        ctx.beginPath(); ctx.arc(s.x * w, s.y * h, s.s, 0, TAU); ctx.fill();
      }

      // --- planet halo (brightens with env) ---------------------------------
      {
        const a = (dark ? 0.08 : 0.06) + env * (dark ? 0.22 : 0.2) + breath * 0.015;
        const g = ctx.createRadialGradient(cx, cy, Rp * 0.85, cx, cy, Rp * 1.9);
        g.addColorStop(0, rgba(haloC, a)); g.addColorStop(0.5, rgba(haloC, a * 0.35)); g.addColorStop(1, rgba(haloC, 0));
        ctx.fillStyle = g; ctx.fillRect(cx - 2 * Rp, cy - 2 * Rp, 4 * Rp, 4 * Rp);
      }

      // --- ring strokes: body lines (overlapping, soft) then grain lines (hairline), then the F ring ---
      const strokeRings = (s0, s1) => {
        for (const pass of [0, 1]) {
          ctx.lineWidth = pass ? 0.45 : 0.85;
          for (const L of S.lines) {
            const a = pass ? L.grain * grainMul : L.body * bodyMul;
            if (a < 0.012) continue;
            ctx.strokeStyle = rgba(pass ? grainCol : bodyCol[L.zone], Math.min(1, a));
            ctx.beginPath(); ctx.arc(0, 0, L.r * Rp * rs, s0, s1); ctx.stroke();
          }
        }
        ctx.lineWidth = 0.5; ctx.strokeStyle = rgba(grainCol, 0.3 * lift);
        ctx.beginPath(); ctx.arc(0, 0, 2.36 * Rp * rs, s0, s1); ctx.stroke();
      };
      // The globe's shadow on the rings: a half-ellipse on the anti-sun side (back, slightly right).
      // Three nested clips grade the edge; inside each, body lines are re-stroked in the shade colour.
      const SHADOW_ANG = -0.7;
      const shadowPass = (s0, s1) => {
        for (const [sc, a] of [[1, dark ? 0.4 : 0.26], [0.88, dark ? 0.3 : 0.2], [0.76, dark ? 0.3 : 0.2]]) {
          ctx.save(); ctx.rotate(SHADOW_ANG);
          ctx.beginPath(); ctx.ellipse(0, 0, 1.6 * Rp * sc, Rp * sc, 0, -Math.PI / 2, Math.PI / 2); ctx.closePath(); ctx.clip();
          ctx.rotate(-SHADOW_ANG); ctx.lineWidth = 0.85;
          for (const L of S.lines) {
            if (L.r > 1.62 * sc) break;
            const al = L.body * bodyMul * a; if (al < 0.012) continue;
            ctx.strokeStyle = rgba(shade, al);
            ctx.beginPath(); ctx.arc(0, 0, L.r * Rp * rs, s0, s1); ctx.stroke();
          }
          ctx.restore();
        }
      };

      // --- rings (far half) with the globe's shadow -----------------------
      ctx.save(); planeSpace(); strokeRings(Math.PI, TAU); shadowPass(Math.PI, TAU); ctx.restore();

      // --- dust grains: Keplerian drift, hidden behind the globe, dimmed in its shadow ---
      const drawDust = (front) => {
        const ux = Math.cos(SHADOW_ANG), uy = Math.sin(SHADOW_ANG);
        for (const d of S.dust) {
          const th = d.a + S.t * 0.14 / Math.pow(d.r, 1.5);
          if ((Math.sin(th) > 0) !== front) continue;
          const [x, y] = toScreen(d.r * rs, th);
          let a = d.al * (0.35 + env * 0.4) * (dark ? 1 : 0.7);
          if (!front) { const dx = x - cx, dy = y - cy; if (dx * dx + dy * dy < Rp * Rp * 1.02) continue; }
          const X = d.r * Math.cos(th), Y = d.r * Math.sin(th);
          const along = X * ux + Y * uy, across = -X * uy + Y * ux;
          if (along > 0 && (along / 1.6) ** 2 + across ** 2 < 1) a *= 0.35;
          ctx.fillStyle = rgba(grainCol, a);
          ctx.beginPath(); ctx.arc(x, y, d.s, 0, TAU); ctx.fill();
        }
      };
      drawDust(false);

      // --- the globe --------------------------------------------------------
      ctx.save();
      ctx.beginPath(); ctx.arc(cx, cy, Rp, 0, TAU); ctx.clip();
      let g = ctx.createRadialGradient(cx - 0.42 * Rp, cy - 0.40 * Rp, 0, cx - 0.2 * Rp, cy - 0.2 * Rp, 1.45 * Rp);
      g.addColorStop(0, lit); g.addColorStop(0.45, mid); g.addColorStop(1, dim);
      ctx.fillStyle = g; ctx.fillRect(cx - Rp, cy - Rp, 2 * Rp, 2 * Rp);
      // latitude bands, and the rings' shadow on the southern hemisphere: front arcs of latitude circles
      ctx.save(); planeSpace();
      const ci = Math.sqrt(1 - k * k) / k;
      const latArc = (lam, s0, s1, ccw) => ctx.arc(0, -Rp * Math.sin(lam) * ci, Rp * Math.cos(lam), s0, s1, ccw);
      const band = (l0, l1, col, a) => { ctx.beginPath(); latArc(l0, 0, Math.PI, false); latArc(l1, Math.PI, 0, true); ctx.closePath(); ctx.fillStyle = rgba(col, a); ctx.fill(); };
      for (const [l0, l1, a, isLit] of BANDS) band(l0, l1, isLit ? lit : dim, a);
      band(-0.50, -0.76, shade, 0.07); band(-0.53, -0.73, shade, 0.08); band(-0.56, -0.70, shade, 0.09);
      ctx.restore();
      // soft terminator and limb darkening
      g = ctx.createRadialGradient(cx - 0.3 * Rp, cy - 0.3 * Rp, 0.45 * Rp, cx - 0.3 * Rp, cy - 0.3 * Rp, 1.5 * Rp);
      g.addColorStop(0, rgba(shade, 0)); g.addColorStop(0.5, rgba(shade, dark ? 0.1 : 0.07)); g.addColorStop(1, rgba(shade, dark ? 0.6 : 0.55));
      ctx.fillStyle = g; ctx.fillRect(cx - Rp, cy - Rp, 2 * Rp, 2 * Rp);
      g = ctx.createRadialGradient(cx, cy, 0.76 * Rp, cx, cy, Rp);
      g.addColorStop(0, rgba(shade, 0)); g.addColorStop(1, rgba(shade, dark ? 0.3 : 0.36));
      ctx.fillStyle = g; ctx.fillRect(cx - Rp, cy - Rp, 2 * Rp, 2 * Rp);
      ctx.restore();

      // --- rings (near half): the ring plane is opaque, so it hides the southern limb ------------
      // Fill each ring band (gaps such as the Cassini division stay open) with the surface colour first,
      // then stroke the lines over it; over the background the fill is invisible, over the globe it occludes.
      if (!S.bands) {
        S.bands = []; let b = null;
        for (const L of S.lines) {
          if (L.body < 0.02) continue;
          if (b && L.r - b[1] < 0.045) b[1] = L.r; else { b = [L.r, L.r]; S.bands.push(b); }
        }
      }
      ctx.save(); planeSpace();
      ctx.fillStyle = rgba(P.surface, dark ? 0.9 : 0.94);
      for (const [r0, r1] of S.bands) {
        if (r1 - r0 < 0.02) continue;
        ctx.beginPath(); ctx.arc(0, 0, (r1 + 0.012) * Rp * rs, 0, Math.PI); ctx.arc(0, 0, Math.max(0.01, r0 - 0.012) * Rp * rs, Math.PI, 0, true); ctx.closePath(); ctx.fill();
      }
      strokeRings(0, Math.PI); shadowPass(0, Math.PI); ctx.restore();
      drawDust(true);

      // --- onset glint: a bright grain slides left → right along the near B ring, with a fading tail ---
      if (!reduce) for (const hh of hits) {
        const u = hh.age / 1.2; if (u >= 1) continue;
        const th = Math.PI * (1 - easeOut(u)), rB = 1.74 * rs, fade = hh.gain * (1 - u) * (1 - u);
        ctx.save(); planeSpace(); ctx.lineWidth = 2.4;
        for (let i = 0; i < 7; i++) {
          const t0 = th + i * 0.05, t1 = t0 + 0.055; if (t1 > Math.PI) break;
          ctx.strokeStyle = rgba(grainCol, fade * 0.55 * (1 - i / 7));
          ctx.beginPath(); ctx.arc(0, 0, rB * Rp, t0, t1); ctx.stroke();
        }
        ctx.restore();
        const [gx, gy] = toScreen(rB, th), gr = 4 + 3 * (1 - u);
        g = ctx.createRadialGradient(gx, gy, 0, gx, gy, gr);
        g.addColorStop(0, rgba(coreC, fade)); g.addColorStop(0.22, rgba(grainCol, fade * 0.7)); g.addColorStop(1, rgba(grainCol, 0));
        ctx.fillStyle = g; ctx.fillRect(gx - gr, gy - gr, 2 * gr, 2 * gr);
      }
    },
  };
})();
