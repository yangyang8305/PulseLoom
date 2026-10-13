// 月与星轨 — a small shaded moon, three nested hairline orbits with slow beads, a sparse star field.
// Light from the upper-left; the sphere is baked per pixel (Lambert) once per theme; craters only on the lit face.
window.OPTION = {
  name: '月与星轨', english: 'Moon & Orbits',
  note: '静止时珠子极慢运行、星点轻闪；震动时月晕随强度变亮、轨道线提亮；每次起音最靠前的珠子闪一下并沿轨道拖出一段淡尾。',

  init(p) {
    const { w, h, cx, cy, R, state } = p;
    let s = 1234567;                                   // fixed-seed LCG → reproducible layout
    const rnd = () => (s = (s * 1664525 + 1013904223) >>> 0) / 4294967296;
    const r = R * 0.3;
    // stars: sparse and evenly spread (min distance), kept out of the orbit ellipse, three brighter ones far apart
    const stars = [];
    let tries = 0;
    while (stars.length < 42 && tries++ < 4000) {
      const x = 30 + rnd() * (w - 60), y = 30 + rnd() * (h - 60);
      const ex = (x - cx) / (R * 1.2), ey = (y - cy) / (R * 0.72);
      if (ex * ex + ey * ey < 1 + rnd() * 0.4) continue;
      if (stars.some(o => Math.hypot(o.x - x, o.y - y) < 30)) continue;
      const big = stars.length % 13 === 4;
      if (big && stars.some(o => o.big && Math.hypot(o.x - x, o.y - y) < 200)) continue;
      stars.push({ x, y, rad: big ? 1.1 + rnd() * 0.25 : 0.4 + rnd() * 0.55, a: big ? 0.8 : 0.22 + rnd() * 0.4,
        T: 1500 + rnd() * 2600, ph: rnd() * 6.283, big });
    }
    // craters: on the lit (upper-left) face only, in moon-local units (fraction of r)
    const L = [-0.6, -0.8];                            // light direction (unit)
    const craters = [];
    while (craters.length < 5) {
      const x = (rnd() * 2 - 1) * 0.9, y = (rnd() * 2 - 1) * 0.9;
      if (Math.hypot(x, y) > 0.88 || x * L[0] + y * L[1] < 0.1) continue;
      if (craters.some(c => Math.hypot(c.x - x, c.y - y) < 0.3)) continue;
      craters.push({ x, y, rad: 0.03 + rnd() * 0.065 });
    }
    // maria: two large, barely-there darker patches on the lit face
    const maria = [{ x: -0.18, y: 0.12, rx: 0.34, ry: 0.22, ang: -0.5 }, { x: 0.12, y: -0.3, rx: 0.2, ry: 0.14, ang: 0.4 }];
    // orbits: nested (never cross), a gentle fan of tilts; only the inner one passes across the moon's face
    const orbits = [
      { a: R * 0.60, k: 0.36, tilt: -0.24, th0: 1.1, spd: 1.00 },
      { a: R * 0.80, k: 0.48, tilt: -0.13, th0: 3.9, spd: -0.72 },
      { a: R * 1.00, k: 0.47, tilt: -0.04, th0: 5.4, spd: 0.55 },
    ];
    Object.assign(state, { r, L, stars, craters, maria, orbits, flash: {} });
  },

  // Shade the sphere per pixel once per theme (Lambert, light from upper-left and slightly in front).
  sphere(p, C) {
    const { ctx, dark, state: S } = p, r = S.r, sc = ctx.getTransform().a || 2, n = Math.ceil(r * 2 * sc);
    if (S.img && S.imgDark === dark) return S.img;
    const cv = document.createElement('canvas'); cv.width = cv.height = n;
    const ic = cv.getContext('2d'), im = ic.createImageData(n, n), d = im.data;
    const rgb = h => [parseInt(h.slice(1, 3), 16), parseInt(h.slice(3, 5), 16), parseInt(h.slice(5, 7), 16)];
    const stops = [[-1, rgb(C.deep)], [-0.3, rgb(C.deep)], [0, rgb(C.shade)], [0.32, rgb(C.mid)], [0.7, rgb(C.lit)], [1, rgb(C.hi)]];
    const Lx = -0.52, Ly = -0.69, Lz = 0.50;                  // normalised light vector
    for (let y = 0; y < n; y++) for (let x = 0; x < n; x++) {
      const nx = (x + 0.5) / n * 2 - 1, ny = (y + 0.5) / n * 2 - 1, dd = Math.hypot(nx, ny);
      const o = (y * n + x) * 4, edge = Math.max(0, Math.min(1, (1 - dd) * r * sc + 0.5));
      if (edge <= 0) continue;
      const nz = Math.sqrt(Math.max(0, 1 - nx * nx - ny * ny));
      let I = nx * Lx + ny * Ly + nz * Lz;                      // Lambert term, negative past the terminator
      I = I >= 0 ? Math.pow(I, 0.85) * (1 - 0.18 * Math.pow(dd, 6)) : I;   // slight limb darkening on the lit face
      let k = 1; while (k < stops.length - 1 && stops[k][0] < I) k++;
      const [a, ca] = stops[k - 1], [b, cb] = stops[k], t = Math.max(0, Math.min(1, (I - a) / (b - a)));
      d[o] = ca[0] + (cb[0] - ca[0]) * t; d[o + 1] = ca[1] + (cb[1] - ca[1]) * t; d[o + 2] = ca[2] + (cb[2] - ca[2]) * t; d[o + 3] = 255 * edge;
    }
    ic.putImageData(im, 0, 0); S.img = cv; S.imgDark = dark;
    return cv;
  },

  draw(p) {
    const { ctx, w, h, cx, cy, R, now, env, hits, rot, breath, palette: P, dark, rgba, reduce, state: S } = p;
    if (!S.orbits) this.init(p);
    const { r, L, stars, craters, maria, orbits } = S;
    const TAU = Math.PI * 2;
    // hex blend (t toward b) so the role colours can sit between palette entries
    const mix = (a, b, t) => '#' + [1, 3, 5].map(i => Math.round(parseInt(a.slice(i, i + 2), 16) * (1 - t) + parseInt(b.slice(i, i + 2), 16) * t).toString(16).padStart(2, '0')).join('');
    // role colors per theme (lit face must be the bright end in both themes)
    const C = dark
      ? { hi: P.ink, lit: P.accent, mid: P.hero3, shade: P.hero2, deep: P.hero1, bead: P.ink, star: P.ink, line: P.line, lineF: P.accent }
      : { hi: mix(P.surface, P.hero1, 0.4), lit: P.hero1, mid: P.hero2, shade: P.hero3, deep: mix(P.accent, P.hero3, 0.3), bead: P.accent, star: P.accent, line: P.line, lineF: P.accent };
    const onset = hits.reduce((m, hh) => m + hh.gain * Math.exp(-hh.age * 3.5), 0); // summed onset energy

    // ---- star field --------------------------------------------------------------------------
    for (const st of stars) {
      const tw = reduce ? 1 : 0.72 + 0.28 * Math.sin(now / st.T + st.ph);
      const a = st.a * tw * (dark ? 0.9 : 0.7) * (1 + env * 0.25);
      if (st.big) {                                     // glint: two hairline rays instead of a blurred halo
        const len = st.rad * 4.2;
        ctx.lineWidth = 0.5; ctx.strokeStyle = rgba(C.star, a * 0.35);
        ctx.beginPath(); ctx.moveTo(st.x - len, st.y); ctx.lineTo(st.x + len, st.y); ctx.moveTo(st.x, st.y - len); ctx.lineTo(st.x, st.y + len); ctx.stroke();
      }
      ctx.fillStyle = rgba(C.star, Math.min(1, a));
      ctx.beginPath(); ctx.arc(st.x, st.y, st.rad, 0, TAU); ctx.fill();
    }

    // ---- orbit geometry helpers ------------------------------------------------------------
    // point on orbit o at angle th → screen xy and depth z (positive = in front of the moon)
    const orbPt = (o, th) => {
      const x = o.a * Math.cos(th), y = o.a * o.k * Math.sin(th);
      const c = Math.cos(o.tilt), s = Math.sin(o.tilt);
      return { x: cx + x * c - y * s, y: cy + x * s + y * c, z: Math.sin(th) };
    };
    const beadTh = o => o.th0 + rot * o.spd;
    const strokeArc = (o, th1, th2, color, alpha, lw) => {   // polyline arc of an orbit
      ctx.beginPath();
      const n = 48;
      for (let i = 0; i <= n; i++) { const q = orbPt(o, th1 + (th2 - th1) * i / n); i ? ctx.lineTo(q.x, q.y) : ctx.moveTo(q.x, q.y); }
      ctx.strokeStyle = rgba(color, alpha); ctx.lineWidth = lw; ctx.stroke();
    };
    // frontmost bead gets assigned to each onset once (keyed by onset birth time)
    let frontIdx = 0, frontZ = -2;
    orbits.forEach((o, i) => { const z = Math.sin(beadTh(o)); if (z > frontZ) { frontZ = z; frontIdx = i; } });
    const flashOf = new Array(orbits.length).fill(0);
    for (const hh of hits) {
      const key = Math.round((now - hh.age * 1000) / 25);
      if (S.flash[key] === undefined) S.flash[key] = frontIdx;
      flashOf[S.flash[key]] += hh.gain * Math.exp(-hh.age * 3.2);
    }
    for (const k in S.flash) if (now - k * 25 > 2000) delete S.flash[k];

    const drawBead = (o, th, flash, front) => {
      const q = orbPt(o, th);
      const depth = 0.78 + 0.22 * q.z;                       // slightly smaller when behind
      const rad = 1.8 * depth, base = (front ? 0.95 : 0.5) * (dark ? 1 : 0.9);
      if (flash > 0.02) {                                     // onset: short fading tail + bloom
        const len = 0.55 * Math.min(1, flash * 1.4), dir = Math.sign(o.spd) || 1, seg = 14;
        for (let i = 0; i < seg; i++) {
          const t0 = th - dir * len * (i + 1) / seg, t1 = th - dir * len * i / seg, f = 1 - i / seg;
          const a = orbPt(o, t0), b = orbPt(o, t1);
          ctx.beginPath(); ctx.moveTo(a.x, a.y); ctx.lineTo(b.x, b.y);
          ctx.strokeStyle = rgba(C.bead, 0.55 * flash * f * f); ctx.lineWidth = 0.5 + 1.1 * f; ctx.stroke();
        }
        const bc = dark ? C.bead : C.hi, ba = dark ? 0.32 : 0.6;   // light theme: a pale bloom so it reads over the moon's shadow too
        const bg = ctx.createRadialGradient(q.x, q.y, 0, q.x, q.y, rad * 5.5);
        bg.addColorStop(0, rgba(bc, ba * flash)); bg.addColorStop(0.4, rgba(bc, ba * 0.3 * flash)); bg.addColorStop(1, rgba(bc, 0));
        ctx.fillStyle = bg; ctx.beginPath(); ctx.arc(q.x, q.y, rad * 5.5, 0, TAU); ctx.fill();
      }
      ctx.fillStyle = rgba(C.bead, Math.min(1, base + flash * 0.4));
      ctx.beginPath(); ctx.arc(q.x, q.y, rad + flash * 0.6, 0, TAU); ctx.fill();
    };

    // ---- back halves of the orbits and beads behind the moon --------------------------------
    const lineA = (dark ? 0.75 : 0.9) * (0.55 + env * 0.3);
    orbits.forEach((o, i) => {
      strokeArc(o, Math.PI, TAU, C.line, lineA * 0.7, 0.6);
      const th = beadTh(o); if (Math.sin(th) <= 0) drawBead(o, th, flashOf[i], false);
    });

    // ---- halo ------------------------------------------------------------------------------
    const haloA = (dark ? 0.16 : 0.26) * (0.42 + 0.1 * breath + env * 1.0 + onset * 0.35);
    const haloR = r * (2.0 + env * 0.3 + onset * 0.12);
    let g = ctx.createRadialGradient(cx, cy, r * 0.85, cx, cy, haloR);
    g.addColorStop(0, rgba(dark ? C.lit : C.mid, haloA)); g.addColorStop(0.45, rgba(dark ? C.lit : C.mid, haloA * 0.28)); g.addColorStop(1, rgba(C.mid, 0));
    ctx.fillStyle = g; ctx.beginPath(); ctx.arc(cx, cy, haloR, 0, TAU); ctx.fill();

    // ---- moon sphere -------------------------------------------------------------------------
    ctx.save();
    ctx.beginPath(); ctx.arc(cx, cy, r, 0, TAU); ctx.clip();
    ctx.drawImage(this.sphere(p, C), cx - r, cy - r, r * 2, r * 2);
    // maria: two soft darker patches (gradient ellipses)
    for (const m of maria) {
      ctx.save(); ctx.translate(cx + m.x * r, cy + m.y * r); ctx.rotate(m.ang); ctx.scale(m.rx, m.ry);
      const mg = ctx.createRadialGradient(0, 0, 0, 0, 0, r);
      mg.addColorStop(0, rgba(C.deep, dark ? 0.14 : 0.08)); mg.addColorStop(0.55, rgba(C.deep, dark ? 0.08 : 0.04)); mg.addColorStop(1, rgba(C.deep, 0));
      ctx.fillStyle = mg; ctx.beginPath(); ctx.arc(0, 0, r, 0, TAU); ctx.fill(); ctx.restore();
    }
    // craters: foreshortened near the limb, inner shadow toward the light, lit rim away from it
    for (const c of craters) {
      const d = Math.hypot(c.x, c.y), sq = Math.sqrt(Math.max(0.08, 1 - d * d));
      const ang = Math.atan2(c.y, c.x), cr = c.rad * r;
      const lit = Math.max(0, c.x * L[0] + c.y * L[1]);          // fade out toward the terminator
      ctx.save();
      ctx.translate(cx + c.x * r, cy + c.y * r); ctx.rotate(ang); ctx.scale(sq, 1); ctx.rotate(-ang);
      const cg = ctx.createRadialGradient(-cr * 0.25, -cr * 0.25, 0, 0, 0, cr);
      cg.addColorStop(0, rgba(C.deep, 0.11 * (0.3 + lit))); cg.addColorStop(0.75, rgba(C.deep, 0.04 * (0.3 + lit))); cg.addColorStop(1, rgba(C.deep, 0));
      ctx.fillStyle = cg; ctx.beginPath(); ctx.arc(0, 0, cr, 0, TAU); ctx.fill();
      ctx.lineWidth = 0.5;
      ctx.strokeStyle = rgba(C.hi, 0.4 * (0.2 + lit)); ctx.beginPath(); ctx.arc(0, 0, cr * 0.85, 0.35, 1.65); ctx.stroke();   // lit far wall
      ctx.strokeStyle = rgba(C.deep, 0.12 * (0.2 + lit)); ctx.beginPath(); ctx.arc(0, 0, cr * 0.85, 3.6, 4.8); ctx.stroke();   // shadowed near wall
      ctx.restore();
    }
    ctx.restore();
    ctx.beginPath(); ctx.arc(cx, cy, r - 0.25, 0, TAU);                 // soft hairline limb so the lit edge still reads on cream
    ctx.strokeStyle = rgba(dark ? C.shade : C.mid, dark ? 0.15 : 0.5); ctx.lineWidth = 0.5; ctx.stroke();

    // ---- front halves of the orbits, beads in front --------------------------------------------
    orbits.forEach((o, i) => {
      strokeArc(o, 0, Math.PI, C.lineF, lineA * 0.62, 0.6);
      const th = beadTh(o); if (Math.sin(th) > 0) drawBead(o, th, flashOf[i], true);
    });
  },
};
