// 织锦经纬 — Silk. A round swatch of plain-woven silk. Fine warp threads (slightly tilted) are crossed by
// denser weft threads; weft rows are dashed with alternating phase so each dash is a thread passing OVER
// one warp, with a hairline highlight above and shadow below every dash so the crossing reads as relief.
// Warp and weft are dyed a shade apart (shot silk). The cloth lies in a few gentle, curved folds that taper
// along their length: threads bunch on the ridges and a strip-wise gradient shades each fold from the
// top-left light. Idle: a specular sheen glides across in ~14 s, the folds drift by a hair. Haptics: the fold
// amplitude and a soft wind follow env; each onset blooms at the centre then sends one radial wave out
// (displacement + a faint luminous crest). Music: both.
window.OPTION = {
  name: '织锦经纬', english: 'Silk',
  note: '静止时高光带每十余秒缓缓扫过一次、褶皱微漂；震动时褶皱随强度被托起，每次起音从中心亮起并荡出一圈波峰；音乐时两者叠加。',

  draw(p) {
    const { ctx, cx, cy, R, now, env, spring, hits, breath, palette: P, dark, reduce, rgba } = p;
    const t = now / 1000, Rc = R * 0.93, TILT = -0.09;
    const SW = 3.6, SF = 2.9;                       // warp spacing, weft spacing (weft is packed denser)
    const lightCol = dark ? P.ink : P.surface, shadeCol = dark ? P.bg : P.hero3;
    const EXT = Rc + 8, box = () => ctx.fillRect(-EXT, -EXT, 2 * EXT, 2 * EXT);

    // --- colours (parsed once per frame)
    const hex = h => [parseInt(h.slice(1, 3), 16), parseInt(h.slice(3, 5), 16), parseInt(h.slice(5, 7), 16)];
    const h1 = hex(P.hero1), h2 = hex(P.hero2), h3 = hex(P.hero3);
    const mix = (a, b, k, al) => `rgba(${(a[0] + (b[0] - a[0]) * k) | 0},${(a[1] + (b[1] - a[1]) * k) | 0},${(a[2] + (b[2] - a[2]) * k) | 0},${al})`;

    // --- folds: nearly vertical ridges, slightly curved, tapering along their length.
    // u runs across the folds, v along them.
    const FB = 0.24, fnx = Math.cos(FB), fny = Math.sin(FB), FL = 124;
    const fphase = reduce ? 0 : t * 0.05 + 0.35 * breath;                    // drifts a few px per 10 s
    const famp = 0.6 + (reduce ? 0 : env * 0.6);                             // folds lift with intensity
    const foldShade = (u, v) => -Math.cos((u / FL) * Math.PI * 2 + fphase - 0.9 + 0.55 * Math.sin(v / 170 + 0.8))
      * (0.55 + 0.45 * Math.sin(v / 150 + 1.3)) * famp;

    // --- displacement field (px): fold bunching + wind that follows env + onset wave packets
    const wind = reduce ? 0 : env * 3;
    const waves = reduce ? [] : hits.map(h => ({ front: h.age * 240, amp: 6 * h.gain * Math.exp(-h.age * 1.6) * Math.min(1, h.age / 0.14) }));
    function disp(x, y) {
      const u = x * fnx + y * fny, v = -x * fny + y * fnx, b = foldShade(u, v) * 2.4;
      let dx = b * fnx, dy = b * fny;
      if (wind) {
        dy += wind * Math.sin(x / 80 + t * 2.2) * (0.5 + 0.5 * Math.sin(y / 110 - t * 1.1));
        dx += wind * 0.3 * Math.sin(y / 90 - t * 1.7 + 1);
      }
      for (const w of waves) {
        const r = Math.hypot(x, y) + 1e-3, d = r - w.front, win = Math.exp(-(d * d) / 2400);
        if (win < 0.02) continue;
        const a = w.amp * win * Math.sin(d / 10) / (1 + r / 130);
        dx += a * x / r; dy += a * y / r;
      }
      return [dx, dy];
    }
    const poly = pts => { ctx.beginPath(); ctx.moveTo(pts[0], pts[1]); for (let i = 2; i < pts.length; i += 2) ctx.lineTo(pts[i], pts[i + 1]); };

    ctx.save();
    ctx.translate(cx, cy);
    const sc = 1 + spring * 0.015; ctx.scale(sc, sc);
    ctx.rotate(TILT);
    ctx.beginPath(); ctx.arc(0, 0, Rc + 4, 0, Math.PI * 2); ctx.clip();

    // --- cloth ground (the colour seen between threads; close to the threads so the grid never shows)
    ctx.fillStyle = dark ? mix(h2, h3, 0.08, 1) : mix(h1, h2, 0.8, 1); box();

    // --- warp (slightly tilted verticals): a shade deeper than the weft, in soft stripes across x
    ctx.lineCap = 'butt'; ctx.lineJoin = 'round'; ctx.lineWidth = 1.6;
    const nW = Math.ceil(Rc / SW);
    for (let k = -nW; k < nW; k++) {
      const x = (k + 0.5) * SW;
      if (Math.abs(x) >= Rc) continue;
      const L = Math.sqrt(Rc * Rc - x * x) + 6;
      const stripe = 0.5 + 0.5 * Math.sin(x / 64 + 0.6) * Math.cos(x / 210);
      ctx.strokeStyle = mix(h2, h3, (dark ? 0.3 : 0.12) + 0.25 * stripe, 0.85);
      const pts = [];
      for (let y = -L; y <= L + 0.01; y += 5) { const [dx, dy] = disp(x, y); pts.push(x + dx, y + dy); }
      poly(pts); ctx.stroke();
    }

    // --- weft (horizontals): dashed so each dash passes OVER one warp, phase alternating per row;
    // a hairline highlight above and shadow below each dash (light from the top-left)
    const nF = Math.ceil(Rc / SF);
    ctx.setLineDash([SW, SW]);
    const hi = rgba(lightCol, dark ? 0.14 : 0.42), sh = rgba(shadeCol, dark ? 0.3 : 0.16);
    for (let j = -nF; j < nF; j++) {
      const y = (j + 0.5) * SF;
      if (Math.abs(y) >= Rc) continue;
      const L = Math.sqrt(Rc * Rc - y * y) + 6, m = Math.ceil(L / SW), x0 = -m * SW;
      const stripe2 = 0.5 + 0.5 * Math.sin(y / 54 - 0.3);
      const pts = [];
      for (let x = x0; x <= -x0 + 0.01; x += 5) { const [dx, dy] = disp(x, y); pts.push(x + dx, y + dy); }
      ctx.lineDashOffset = ((m & 1) ^ ((j + 1000) & 1)) ? SW : 0;
      ctx.save(); ctx.translate(0, 0.9); ctx.lineWidth = 1.7; ctx.strokeStyle = sh; poly(pts); ctx.stroke(); ctx.restore();
      ctx.save(); ctx.translate(0, -0.9); ctx.lineWidth = 0.9; ctx.strokeStyle = hi; poly(pts); ctx.stroke(); ctx.restore();
      ctx.lineWidth = 1.7;
      ctx.strokeStyle = dark ? mix(h2, h3, 0.42 + 0.18 * stripe2, 0.9) : mix(h1, h2, 0.55 + 0.3 * stripe2, 0.9);
      poly(pts); ctx.stroke();
    }
    ctx.setLineDash([]);

    // --- fold shading: strips across u, each a gradient along v (so folds curve and taper)
    ctx.save(); ctx.rotate(FB);                       // now x ≡ u, y ≡ v
    const NS = 44, sw = (2 * EXT) / NS, la = dark ? 0.1 : 0.3, da = dark ? 0.3 : 0.15;
    for (let i = 0; i < NS; i++) {
      const u = -EXT + (i + 0.5) * sw, g = ctx.createLinearGradient(0, -EXT, 0, EXT);
      for (let k = 0; k <= 8; k++) {
        const v = -EXT + (2 * EXT * k) / 8, s = foldShade(u, v);
        g.addColorStop(k / 8, s > 0 ? rgba(lightCol, s * la) : rgba(shadeCol, -s * da));
      }
      ctx.fillStyle = g; ctx.fillRect(u - sw / 2 - 0.3, -EXT, sw + 0.6, 2 * EXT);
    }
    ctx.restore();

    // --- lighting: a broad glow from the top-left, a touch of depth toward the bottom-right
    let g = ctx.createRadialGradient(-Rc * 0.5, -Rc * 0.55, 0, -Rc * 0.25, -Rc * 0.25, Rc * 1.45);
    g.addColorStop(0, rgba(lightCol, dark ? 0.08 : 0.28)); g.addColorStop(0.55, rgba(lightCol, 0));
    g.addColorStop(1, rgba(shadeCol, dark ? 0.18 : 0.1));
    ctx.fillStyle = g; box();

    // --- onsets: a soft bloom at the centre that becomes a luminous crest travelling with the wave
    const flash = hits.reduce((a, h) => Math.max(a, h.gain * Math.exp(-h.age * 5)), 0);
    if (flash > 0.01) {
      g = ctx.createRadialGradient(0, 0, 0, 0, 0, 46);
      g.addColorStop(0, rgba(lightCol, flash * (dark ? 0.22 : 0.5))); g.addColorStop(1, rgba(lightCol, 0));
      ctx.fillStyle = g; box();
    }
    for (const w of waves) {
      if (w.front < 10) continue;
      const a = Math.min(1, w.amp / 6) * (dark ? 0.14 : 0.32);
      g = ctx.createRadialGradient(0, 0, Math.max(0, w.front - 28), 0, 0, w.front + 28);
      g.addColorStop(0, rgba(lightCol, 0)); g.addColorStop(0.5, rgba(lightCol, a)); g.addColorStop(1, rgba(lightCol, 0));
      ctx.fillStyle = g; box();
    }

    // --- sheen: a specular band along the warp direction that glides across in ~14 s, brighter on onsets
    const u0 = (reduce ? 0.1 : -1.5 + ((now / 14000) % 1) * 3.0) * Rc;
    const peak = (dark ? 0.12 : 0.3) * (0.8 + 0.2 * breath) + flash * (dark ? 0.07 : 0.15) + env * (dark ? 0.03 : 0.05);
    const band = (uc, half, a) => {
      const gg = ctx.createLinearGradient(fnx * (uc - half), fny * (uc - half), fnx * (uc + half), fny * (uc + half));
      gg.addColorStop(0, rgba(lightCol, 0)); gg.addColorStop(0.35, rgba(lightCol, a * 0.45));
      gg.addColorStop(0.5, rgba(lightCol, a)); gg.addColorStop(0.65, rgba(lightCol, a * 0.45)); gg.addColorStop(1, rgba(lightCol, 0));
      ctx.fillStyle = gg; box();
    };
    band(u0, Rc * 0.4, peak);
    band(u0 - Rc * 0.5, Rc * 0.18, peak * 0.45);

    // --- soft edge: a short feather so the swatch stays a definite disc
    g = ctx.createRadialGradient(0, 0, Rc * 0.85, 0, 0, Rc + 1);
    g.addColorStop(0, rgba(P.surface, 0)); g.addColorStop(0.45, rgba(P.surface, 0.35)); g.addColorStop(1, rgba(P.surface, 1));
    ctx.fillStyle = g; box();
    ctx.restore();
  },
};
