// Shared rhythm engine for the Pulse Loom artwork options. Deterministic: no Date/random inside step().
// Signal model mirrors the app: a level in [0,1] from haptic segments or a music energy curve.
(function () {
  const T = (d, g, gain) => ({ type: 'transient', d, g, gain });
  const C = (d, g, gain) => ({ type: 'continuous', d, g, gain });
  const rhythms = {
    bloom: { name: '柔绽', sub: '轻震、停歇', cycle: 2000, segs: [C(120, 0, .35), C(160, 0, .8), C(220, 0, 1), C(240, 0, .55), C(180, 1080, .25)] },
    heart: { name: '心跳', sub: '平稳的脉搏', cycle: 1000, segs: [T(30, 110, 1), T(30, 830, .65)] },
    tabla: { name: '塔布拉', sub: '十六拍一循环', cycle: 2400, segs: 'dha dhin dhin dha dha dhin dhin dha dha tin tin ta ta dhin dhin dha'.split(' ').map(b => T(30, 120, b === 'dha' ? 1 : b === 'dhin' ? .75 : b === 'tin' ? .5 : .6)) },
    wave: { name: '缓浪', sub: '长浪起伏', cycle: 4000, segs: [C(500, 0, .2), C(500, 0, .5), C(500, 0, .85), C(500, 0, 1), C(500, 0, .7), C(500, 0, .4), C(500, 500, .15)] },
    music: { name: '心潮', sub: '合成器 · 112 bpm', cycle: 2143, segs: null },
  };
  function segLevel(r, t) {
    let x = t % r.cycle, acc = 0;
    for (const s of r.segs) {
      const local = x - acc;
      if (local < 0) break;
      if (local < s.d) return s.gain;
      if (local < s.d + s.g) return s.type === 'transient' ? s.gain * Math.max(0, 1 - (local - s.d) / 120) : 0;
      acc += s.d + s.g;
    }
    return 0;
  }
  function musicLevel(t) {
    const beat = 60000 / 112, x = (t % (beat * 4)) / beat;
    const kick = Math.max(0, 1 - ((t % beat) / 110)), clap = (x % 2 >= 1 && x % 2 < 1.12) ? .8 : 0;
    const phrase = .35 + .25 * Math.sin(t / 4300) + .15 * Math.sin(t / 900);
    return Math.min(1, phrase * .7 + kick * .7 + clap);
  }
  function levelAt(mode, t, gain) {
    if (!mode || mode === 'idle') return 0;
    const r = rhythms[mode];
    return (r.segs ? segLevel(r, t) : musicLevel(t)) * gain;
  }

  // Engine state advanced by step(dt). `hits` are onsets within the last 1.6 s: {born, gain}.
  function createEngine() {
    return { env: 0, prev: 0, spring: 0, springV: 0, rot: 0, hits: [], time: 0 };
  }
  function step(e, lv, dtMs, reduce) {
    const dt = Math.min(50, dtMs) / 1000;
    e.time += dtMs;
    e.env += (lv - e.env) * (lv > e.env ? 0.45 : 0.06);
    if (lv - e.prev > 0.28 && !reduce) { e.springV += 2.4 * lv; e.hits.push({ born: e.time, gain: lv }); }
    e.prev = lv;
    e.springV += (-90 * e.spring - 9 * e.springV) * dt; e.spring += e.springV * dt;
    if (!reduce) e.rot += dt * (0.08 + e.env * 0.3);
    for (let i = e.hits.length - 1; i >= 0; i--) if (e.time - e.hits[i].born > 1600) e.hits.splice(i, 1);
    // breath: a slow 10 s idle cycle
    e.breath = reduce ? 0 : 0.5 + 0.5 * Math.sin(e.time / 1600);
  }
  function hex(n) { return parseInt(n.slice(1), 16); }
  function rgba(h, a) { const n = hex(h); return `rgba(${n >> 16 & 255},${n >> 8 & 255},${n & 255},${a})`; }
  function luminance(h) { const n = hex(h); return (0.2126 * (n >> 16 & 255) + 0.7152 * (n >> 8 & 255) + 0.0722 * (n & 255)) / 255; }

  const palettes = {
    light: { bg: '#fcf7f3', surface: '#fffcf9', ink: '#423238', muted: '#806d75', line: '#dfced3', accent: '#966879', hero1: '#f7e8e7', hero2: '#e7c6d1', hero3: '#c7a2b9' },
    dark: { bg: '#161416', surface: '#222024', ink: '#f2ecef', muted: '#c0b0ba', line: '#4b4148', accent: '#dab7c6', hero1: '#3a2f36', hero2: '#5a4252', hero3: '#8a6a7c' },
  };

  window.LoomEngine = { rhythms, levelAt, createEngine, step, rgba, luminance, palettes };
})();
