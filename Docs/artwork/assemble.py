#!/usr/bin/env python3
"""Build gallery.html: engine + every option inlined, tabs, rhythm chips, theme toggle, notes."""
import json, re, sys
from pathlib import Path

ART = Path(__file__).resolve().parent
ranked = json.loads((ART / "ranked.json").read_text())
# restraint: every option is drawn at reduced opacity over the surface, Saturn more so
TONE = {"saturn": 0.66, "water": 0.9, "mandala": 0.82, "guilloche": 0.82, "moon": 0.84, "ink": 1.0, "silk": 0.82, "lotus": 0.78}  # [{direction,title,name,english,note,highlights,average,votes,...}]
engine = (ART / "engine.js").read_text()
options_js = []
for r in ranked:
    src = (ART / "options" / f"{r['direction']}.js").read_text()
    # wrap each option file so its window.OPTION assignment lands in a registry
    src = src.replace("window.OPTION =", "__opt =", 1)
    options_js.append(f"(function(){{ let __opt; {src}\n window.LOOM_OPTIONS['{r['direction']}'] = __opt; }})();")

tabs = "".join(
    f'<button class="chip" data-m="{r["direction"]}" aria-pressed="{"true" if i == 0 else "false"}">{r["name"]}</button>'
    for i, r in enumerate(ranked))
notes = {r["direction"]: {"name": r["name"], "english": r["english"], "note": r["note"],
                          "highlights": r.get("highlights", []), "score": r.get("average")} for r in ranked}

html = f'''<title>Pulse Loom 主图工作室</title>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Cormorant+Garamond:ital,wght@0,500;1,500&display=swap">
<style>
/* Layout: phone column. Option tabs, the stage, rhythm chips, dock, then the designer's note. */
:root{{
  --bg:#fcf7f3; --surface:#fffcf9; --ink:#423238; --muted:#806d75; --line:#dfced3;
  --accent:#966879; --hero1:#f7e8e7; --hero2:#e7c6d1; --hero3:#c7a2b9; --on-accent:#fffaf8;
  --display:"Cormorant Garamond",Georgia,"Songti SC",serif;
  --body:-apple-system,BlinkMacSystemFont,"PingFang SC","Hiragino Sans",sans-serif;
}}
@media (prefers-color-scheme: dark){{ :root:not([data-theme="light"]){{
  --bg:#161416; --surface:#222024; --ink:#f2ecef; --muted:#c0b0ba; --line:#4b4148;
  --accent:#dab7c6; --hero1:#3a2f36; --hero2:#5a4252; --hero3:#8a6a7c; --on-accent:#271c24; color-scheme:dark }} }}
:root[data-theme="dark"]{{
  --bg:#161416; --surface:#222024; --ink:#f2ecef; --muted:#c0b0ba; --line:#4b4148;
  --accent:#dab7c6; --hero1:#3a2f36; --hero2:#5a4252; --hero3:#8a6a7c; --on-accent:#271c24; color-scheme:dark }}
html,body{{height:100%}}
body{{margin:0;background:var(--bg);color:var(--ink);font-family:var(--body);padding-inline:16px;padding-block:12px 24px}}
.wrap{{max-width:440px;margin:0 auto;display:flex;flex-direction:column;gap:12px}}
header{{display:flex;align-items:baseline;justify-content:space-between;gap:12px}}
h1{{font-family:var(--display);font-style:italic;font-weight:500;font-size:28px;margin:0}}
.tools{{display:flex;gap:8px;align-items:center}}
.row{{display:flex;gap:8px;overflow-x:auto;padding:2px;scrollbar-width:none}}
.row::-webkit-scrollbar{{display:none}}
.chip{{flex:0 0 auto;min-height:40px;padding:8px 14px;border-radius:999px;border:0.8px solid var(--line);
  background:color-mix(in srgb,var(--surface) 90%,transparent);color:var(--ink);font:inherit;font-size:14px;cursor:pointer}}
.chip[aria-pressed="true"]{{background:var(--accent);color:var(--on-accent);border-color:transparent;box-shadow:0 6px 18px -8px var(--accent)}}
.chip:focus-visible,.btn:focus-visible{{outline:2px solid var(--accent);outline-offset:2px}}
.stage{{position:relative;aspect-ratio:440/470;max-width:100%;border-radius:22px;overflow:hidden;background:var(--surface);border:0.8px solid var(--line)}}
canvas{{position:absolute;inset:0;width:100%;height:100%;display:block}}
.nameplate{{position:absolute;left:0;right:0;bottom:12px;text-align:center;pointer-events:none}}
.nameplate b{{font-family:var(--display);font-weight:500;font-size:24px;display:block;line-height:1.1}}
.nameplate span{{color:var(--muted);font-size:12px}}
.dock{{display:flex;gap:10px;align-items:center}}
.btn{{flex:1;min-height:46px;border-radius:999px;border:0;font:inherit;font-size:16px;cursor:pointer;color:var(--on-accent);
  background:linear-gradient(180deg,color-mix(in srgb,var(--accent) 85%,white),var(--accent));box-shadow:0 10px 24px -12px var(--accent)}}
.btn.secondary{{flex:0 0 auto;padding-inline:18px;background:var(--surface);color:var(--ink);border:0.8px solid var(--line);box-shadow:none}}
.note{{font-size:13px;line-height:1.6;color:var(--muted)}}
.note b{{color:var(--ink);font-size:15px}}
.note ul{{margin:6px 0 0;padding-left:18px}}
.note li{{margin:2px 0}}
</style>

<div class="wrap">
  <header><h1>Pulse Loom</h1>
    <div class="tools"><button class="chip" id="theme" aria-pressed="false">深色</button></div>
  </header>
  <div class="row" id="modes" role="tablist" aria-label="方案">{tabs}</div>
  <div class="stage"><canvas id="art" aria-hidden="true"></canvas>
    <div class="nameplate"><b id="name">柔绽</b><span id="sub">轻震、停歇</span></div></div>
  <div class="row" id="rhythms" role="group" aria-label="节奏">
    <button class="chip" data-r="bloom" aria-pressed="true">柔绽</button>
    <button class="chip" data-r="heart" aria-pressed="false">心跳</button>
    <button class="chip" data-r="tabla" aria-pressed="false">塔布拉</button>
    <button class="chip" data-r="wave" aria-pressed="false">缓浪</button>
    <button class="chip" data-r="music" aria-pressed="false">音乐 112 bpm</button>
  </div>
  <div class="dock"><button class="btn" id="play">▶ 开始震动</button><button class="btn secondary" id="stop">■ 停止</button></div>
  <div class="note" id="note"></div>
</div>

<script>
{engine}
window.LOOM_OPTIONS = {{}};
{chr(10).join(options_js)}
(() => {{
  const E = window.LoomEngine, notes = {json.dumps(notes, ensure_ascii=False)}, TONE = {json.dumps(TONE)};
  const canvas = document.getElementById('art'), ctx = canvas.getContext('2d');
  const reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;
  const ids = Object.keys(window.LOOM_OPTIONS);
  let mode = ids[0], rhythm = 'bloom', playing = false, t0 = 0, gain = 0.85;
  let eng = E.createEngine(), state = {{}};
  const isDark = () => {{
    const t = document.documentElement.getAttribute('data-theme');
    return t ? t === 'dark' : matchMedia('(prefers-color-scheme: dark)').matches;
  }};
  let last = performance.now();
  function frame(now) {{
    const dtMs = Math.min(50, now - last); last = now;
    const dpr = devicePixelRatio || 1, w = canvas.clientWidth, h = canvas.clientHeight;
    if (canvas.width !== Math.round(w * dpr) || canvas.height !== Math.round(h * dpr)) {{ canvas.width = Math.round(w * dpr); canvas.height = Math.round(h * dpr); }}
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    const lv = playing ? E.levelAt(rhythm, now - t0, gain) : 0;
    E.step(eng, lv, dtMs, reduce);
    const pal = E.palettes[isDark() ? 'dark' : 'light'];
    ctx.fillStyle = pal.surface; ctx.fillRect(0, 0, w, h);
    const opt = window.LOOM_OPTIONS[mode];
    const scale = Math.min(w / 440, h / 470);
    ctx.save(); ctx.translate((w - 440 * scale) / 2, (h - 470 * scale) / 2); ctx.scale(scale, scale);
    const p = {{ ctx, w: 440, h: 470, cx: 220, cy: 470 * 0.46, R: 176, now: eng.time, dt: dtMs / 1000,
      env: eng.env, spring: eng.spring, hits: eng.hits.map(x => ({{ age: (eng.time - x.born) / 1000, gain: x.gain }})), rot: eng.rot, breath: eng.breath,
      palette: pal, dark: isDark(), reduce, state, rgba: E.rgba, playing }};
    ctx.globalAlpha = TONE[mode] || 0.85;
    try {{ if (opt.tick) opt.tick({{ dt: dtMs / 1000, now: eng.time, env: eng.env, state }}); opt.draw(p); }} catch (e) {{ console.error(mode, e); }}
    ctx.globalAlpha = 1;
    ctx.restore();
    requestAnimationFrame(frame);
  }}
  requestAnimationFrame(frame);

  const noteEl = document.getElementById('note');
  function showNote() {{
    const n = notes[mode];
    noteEl.innerHTML = `<b>${{n.name}} · ${{n.english}}</b><br>${{n.note}}` + (n.highlights.length ? `<ul>${{n.highlights.map(h => `<li>${{h}}</li>`).join('')}}</ul>` : '');
  }}
  showNote();
  document.getElementById('modes').addEventListener('click', (e) => {{
    const b = e.target.closest('.chip'); if (!b) return;
    for (const c of e.currentTarget.querySelectorAll('.chip')) c.setAttribute('aria-pressed', String(c === b));
    mode = b.dataset.m; state = {{}}; eng = E.createEngine(); showNote();
  }});
  const nameEl = document.getElementById('name'), subEl = document.getElementById('sub');
  document.getElementById('rhythms').addEventListener('click', (e) => {{
    const b = e.target.closest('.chip'); if (!b) return;
    for (const c of e.currentTarget.querySelectorAll('.chip')) c.setAttribute('aria-pressed', String(c === b));
    rhythm = b.dataset.r; nameEl.textContent = E.rhythms[rhythm].name; subEl.textContent = E.rhythms[rhythm].sub;
    if (playing) t0 = performance.now();
  }});
  const playBtn = document.getElementById('play');
  playBtn.addEventListener('click', () => {{ playing = !playing; t0 = performance.now(); playBtn.textContent = playing ? '❚❚ 暂停' : '▶ 开始震动'; }});
  document.getElementById('stop').addEventListener('click', () => {{ playing = false; playBtn.textContent = '▶ 开始震动'; }});
  const themeBtn = document.getElementById('theme');
  themeBtn.addEventListener('click', () => {{
    const dark = !isDark();
    document.documentElement.setAttribute('data-theme', dark ? 'dark' : 'light');
    themeBtn.textContent = dark ? '浅色' : '深色'; themeBtn.setAttribute('aria-pressed', String(dark));
  }});
  themeBtn.textContent = isDark() ? '浅色' : '深色';
}})();
</script>
'''
(ART / "gallery.html").write_text(html)
print("gallery.html", len(html) // 1024, "KB", len(ranked), "options")

app_html = f"""<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<style>html,body{{margin:0;height:100%;background:transparent;overflow:hidden;-webkit-user-select:none}}canvas{{position:absolute;inset:0;width:100%;height:100%;display:block}}</style>
<canvas id="art"></canvas>
<script>
{engine}
window.LOOM_OPTIONS = {{}};
{chr(10).join(options_js)}
(() => {{
  const E = window.LoomEngine, TONE = {json.dumps(TONE)};
  const canvas = document.getElementById('art'), ctx = canvas.getContext('2d');
  let option = 'saturn', level = 0, playing = false, reduce = false, pal = E.palettes.light, dark = false;
  let eng = E.createEngine(), state = {{}}, last = performance.now();
  function frame(now) {{
    const dtMs = Math.min(50, now - last); last = now;
    const dpr = devicePixelRatio || 1, w = canvas.clientWidth, h = canvas.clientHeight;
    if (!w || !h) {{ requestAnimationFrame(frame); return; }}
    if (canvas.width !== Math.round(w * dpr) || canvas.height !== Math.round(h * dpr)) {{ canvas.width = Math.round(w * dpr); canvas.height = Math.round(h * dpr); }}
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0); ctx.clearRect(0, 0, w, h);
    E.step(eng, playing ? level : 0, dtMs, reduce);
    const opt = window.LOOM_OPTIONS[option] || window.LOOM_OPTIONS.saturn;
    const scale = Math.min(w / 440, h / 470);
    ctx.save(); ctx.translate((w - 440 * scale) / 2, (h - 470 * scale) / 2); ctx.scale(scale, scale);
    ctx.globalAlpha = TONE[option] || 0.85;
    const p = {{ ctx, w: 440, h: 470, cx: 220, cy: 470 * 0.5, R: 176, now: eng.time, dt: dtMs / 1000, env: eng.env, spring: eng.spring,
      hits: eng.hits.map(x => ({{ age: (eng.time - x.born) / 1000, gain: x.gain }})), rot: eng.rot, breath: eng.breath, palette: pal, dark, reduce, state, rgba: E.rgba, playing }};
    try {{ if (opt.tick) opt.tick({{ dt: dtMs / 1000, now: eng.time, env: eng.env, state }}); opt.draw(p); }} catch (e) {{}}
    ctx.restore(); ctx.globalAlpha = 1;
    requestAnimationFrame(frame);
  }}
  requestAnimationFrame(frame);
  window.loom = {{
    set(l, p) {{ level = Math.max(0, Math.min(1, +l || 0)); playing = !!p; }},
    configure(c) {{
      if (c.option && c.option !== option) {{ option = c.option; state = {{}}; eng = E.createEngine(); }}
      if (c.palette) pal = c.palette; if ('dark' in c) dark = !!c.dark; if ('reduce' in c) reduce = !!c.reduce;
    }},
  }};
}})();
</script>
"""
(ART / "LoomArt.html").write_text(app_html)
print("LoomArt.html", len(app_html) // 1024, "KB")
