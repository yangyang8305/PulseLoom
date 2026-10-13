// 金线曼陀罗 — Gilt Mandala. A jali / rangoli style badge drawn in 0.5–0.9 px accent hairlines.
// Seven layers, outside → in: scalloped rim, hairline ring, bead ring, 16 double-lined lotus petals,
// interlaced 8-point star (two squares, woven over/under), 12 small arches, 6-petal rosette + dot.
// Motion: each layer counter-rotates at its own glacial speed; env lifts line brightness and opens the
// petals; every onset sends a brightness wave outward, each layer lit after a delay ∝ its radius.
(function () {
  const TAU = Math.PI * 2, LIGHT = -2.4;                    // light source: upper left
  const SPEED = { rim: 0.10, ring: -0.07, bead: -0.14, petal: 0.06, star: -0.20, arch: 0.16, rose: -0.28 };
  const pol = (r, a) => [Math.cos(a) * r, Math.sin(a) * r];

  function draw(p) {
    const { ctx, cx, cy, R, env, spring, hits, rot, breath, palette: P, dark, rgba, reduce } = p;
    const A = P.accent, HI = dark ? P.ink : P.surface, tame = dark ? 0.86 : 1;              // dark accent is brighter: pull it back a little
    const base = (0.85 + 0.15 * breath) * (1 + 0.45 * env);  // breath + intensity lift
    // Brightness wave: an onset reaches radius fraction r after r*0.30 s, snaps on, then decays.
    const wave = r => {
      let s = 0;
      for (const h of hits) { const u = h.age - r * 0.30; if (u > 0) s += h.gain * (u < 0.035 ? u / 0.035 : Math.exp(-(u - 0.035) / 0.32)); }
      return Math.min(1.2, s);
    };
    const lit = a => 0.70 + 0.30 * Math.cos(a - LIGHT);    // metallic: brighter facing the light
    const alpha = (b, wv, a) => Math.min(1, b * tame * lit(a) * (base + 0.9 * wv));
    const stroke = (w, b, wv, a) => { ctx.lineWidth = w; ctx.strokeStyle = rgba(A, alpha(b, wv, a)); };
    const open = reduce ? 0 : Math.max(0, env * 0.035 + spring * 0.02);  // petal opening (radius fraction)

    ctx.save(); ctx.translate(cx, cy); ctx.lineCap = 'round'; ctx.lineJoin = 'round';

    // 0. A barely-there warm disc, offset toward the light, to lift the badge from the surface
    const g = ctx.createRadialGradient(-R * 0.15, -R * 0.15, 0, 0, 0, R * 1.02);
    g.addColorStop(0, rgba(P.hero1, (dark ? 0.5 : 0.8) * (0.55 + 0.45 * env)));
    g.addColorStop(1, rgba(P.hero1, 0));
    ctx.fillStyle = g; ctx.beginPath(); ctx.arc(0, 0, R * 1.02, 0, TAU); ctx.fill();

    // ---- helpers ---------------------------------------------------------------------------------
    // ring: a hairline circle drawn in 36 arcs so the alpha can follow the light
    function ring(rf, w, b, th) {
      const wv = wave(rf), r = R * rf * (1 + 0.012 * wv), n = 36;
      ctx.lineCap = 'butt';
      for (let i = 0; i < n; i++) {
        const a0 = th + i * TAU / n, a1 = a0 + TAU / n + 0.004;
        stroke(w, b, wv, a0 + TAU / n / 2); ctx.beginPath(); ctx.arc(0, 0, r, a0, a1); ctx.stroke();
      }
      ctx.lineCap = 'round';
    }
    // rim: n tiny outward scallops sitting on a hairline ring
    function rim(rf, n, th) {
      const wv = wave(rf), r = R * rf * (1 + 0.012 * wv), s = Math.PI * r / n;
      ring(rf, 0.5, 0.28, th);
      for (let i = 0; i < n; i++) {
        const a = th + i * TAU / n, [x, y] = pol(r, a);
        stroke(0.55, 0.36, wv, a); ctx.beginPath(); ctx.arc(x, y, s, a - Math.PI / 2, a + Math.PI / 2); ctx.stroke();
      }
    }
    // beads: n filled dots with a speck of highlight toward the light
    function beads(rf, n, th) {
      const wv = wave(rf), r = R * rf * (1 + 0.012 * wv);
      for (let i = 0; i < n; i++) {
        const a = th + i * TAU / n, [x, y] = pol(r, a);
        ctx.fillStyle = rgba(A, alpha(0.62, wv, a)); ctx.beginPath(); ctx.arc(x, y, 1.5, 0, TAU); ctx.fill();
        ctx.fillStyle = rgba(HI, 0.55); ctx.beginPath(); ctx.arc(x - 0.45, y - 0.45, 0.5, 0, TAU); ctx.fill();
      }
    }
    // petal outline in local coords, pointing along +x: base at r0 (half width wb), tip at r1
    function petalPath(r0, r1, wb, wm, wt) {
      const L = r1 - r0;
      ctx.beginPath(); ctx.moveTo(r0, -wb);
      ctx.bezierCurveTo(r0 + L * 0.30, -wm, r1 - L * 0.25, -wt, r1, 0);
      ctx.bezierCurveTo(r1 - L * 0.25, wt, r0 + L * 0.30, wm, r0, wb);
      ctx.closePath();
    }
    function petals(n, th) {
      const wv = wave(0.66), r0 = R * 0.505, r1 = R * (0.82 + open) * (1 + 0.010 * wv), k = 1 + 0.08 * env;
      for (let i = 0; i < n; i++) {
        const a = th + i * TAU / n;
        ctx.save(); ctx.rotate(a);
        // faint inner fill (brightens a little with intensity)
        petalPath(r0 + 2.8, r1 - 4.5, 6.4 * k, 13.9 * k, 5.2 * k);
        ctx.fillStyle = rgba(P.hero2, (dark ? 0.45 : 0.22) * (0.8 + 0.5 * env + 0.4 * wv)); ctx.fill();
        stroke(0.55, 0.42, wv, a); ctx.stroke();                     // inner line
        petalPath(r0, r1, 9 * k, 16.5 * k, 7.4 * k);
        stroke(0.8, 0.72, wv, a); ctx.stroke();                      // outer line
        stroke(0.5, 0.30, wv, a); ctx.beginPath(); ctx.moveTo(r0 + 8, 0); ctx.lineTo(r1 - 10, 0); ctx.stroke(); // midrib
        ctx.restore();
      }
    }
    // star: two squares (circumradius rs) woven over/under. Every edge passes under the other square
    // at 70.7 % of its length and over it at 29.3 %, so a true gap there is all the weaving needs.
    function star(rf, th) {
      const wv = wave(rf * 0.85), rs = R * rf * (1 + 0.012 * wv), gp = 2.3 / (rs * Math.SQRT2), tc = 1 - Math.SQRT1_2;
      ring(rf, 0.5, 0.30, th);                                        // seat ring shared with the petal bases
      for (let q = 0; q < 2; q++) for (let i = 0; i < 4; i++) {
        const a0 = th + q * Math.PI / 4 + i * Math.PI / 2, [x0, y0] = pol(rs, a0), [x1, y1] = pol(rs, a0 + Math.PI / 2);
        const at = t => [x0 + (x1 - x0) * t, y0 + (y1 - y0) * t];
        stroke(0.8, 0.70, wv, a0 + Math.PI / 4); ctx.beginPath();
        ctx.moveTo(x0, y0); ctx.lineTo(...at(tc - gp)); ctx.moveTo(...at(tc + gp)); ctx.lineTo(x1, y1); ctx.stroke();
      }
    }
    // arches: n lancet arches on a hairline ring — parallel jambs climb straight, then meet in a point
    function arches(n, th) {
      const wv = wave(0.27), rb = R * 0.235 * (1 + 0.012 * wv), ra = R * 0.325 * (1 + 0.012 * wv);
      const wb = rb * Math.sin(0.36 * TAU / n), rm = rb + (ra - rb) * 0.60;
      ring(0.235, 0.5, 0.30, th);
      for (let i = 0; i < n; i++) {
        ctx.save(); ctx.rotate(th + i * TAU / n);
        stroke(0.65, 0.55, wv, th + i * TAU / n); ctx.beginPath(); ctx.moveTo(rb, -wb);
        ctx.bezierCurveTo(rm, -wb, rm + (ra - rm) * 0.5, -wb * 0.32, ra, 0);
        ctx.bezierCurveTo(rm + (ra - rm) * 0.5, wb * 0.32, rm, wb, rb, wb); ctx.stroke();
        ctx.restore();
      }
    }
    // rosette: six petals of arcs around a centre dot, enclosed by a hairline ring
    function rosette(th) {
      const wv = wave(0.12), rf = R * 0.15 * (1 + 0.012 * wv);
      ring(0.19, 0.5, 0.34, th);
      for (let i = 0; i < 6; i++) {
        const a = th + i * TAU / 6, [tx, ty] = pol(rf, a), [l0, l1] = pol(rf * 0.62, a - 0.52), [r0, r1] = pol(rf * 0.62, a + 0.52);
        ctx.beginPath(); ctx.moveTo(0, 0); ctx.quadraticCurveTo(l0, l1, tx, ty); ctx.quadraticCurveTo(r0, r1, 0, 0);
        ctx.fillStyle = rgba(P.hero2, (dark ? 0.45 : 0.22) * (0.8 + 0.5 * env + 0.4 * wv)); ctx.fill();
        stroke(0.75, 0.78, wv, a); ctx.stroke();
      }
      const wd = wave(0), rd = 2.4 + 0.6 * wd;
      ctx.fillStyle = rgba(A, alpha(0.95, wd, LIGHT)); ctx.beginPath(); ctx.arc(0, 0, rd, 0, TAU); ctx.fill();
      ctx.fillStyle = rgba(HI, 0.7); ctx.beginPath(); ctx.arc(-rd * 0.34, -rd * 0.34, rd * 0.26, 0, TAU); ctx.fill();
    }

    // ---- layers, outside → in ------------------------------------------------------------------
    const up = -Math.PI / 2;
    rim(0.965, 88, up + rot * SPEED.rim);
    ring(0.925, 0.5, 0.26, up + rot * SPEED.ring);
    beads(0.885, 72, up + rot * SPEED.bead);
    petals(16, up + rot * SPEED.petal);
    star(0.50, up + rot * SPEED.star);
    arches(12, up + rot * SPEED.arch);
    rosette(up + rot * SPEED.rose);

    ctx.restore();
  }

  window.OPTION = {
    name: '金线曼陀罗', english: 'Gilt Mandala',
    note: '静止时七层细线以各自极慢的速度正反旋转并随呼吸微明暗；震动时线条随强度变亮、莲瓣略张；每次起音一道亮度波从中心逐层向外传过去。',
    draw,
  };
})();
