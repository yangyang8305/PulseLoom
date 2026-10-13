#!/usr/bin/env python3
"""Deterministic haptic compositions ("pieces"): longer, structured programmes built from the same
Segment model as the loops. Output: Packages/PulseLoomCore/Sources/PulseLoomCore/Resources/pieces.json.
Every piece peaks at 1.0 so the intensity slider's 100% is the device ceiling."""
import json, math, random, uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "Packages/PulseLoomCore/Sources/PulseLoomCore/Resources/pieces.json"
NS = uuid.UUID("7d6b2a6e-6c1c-4d8e-9e4e-0b1f1a9f7c21")

class Score:
    def __init__(self):
        self.segments = []
    def cont(self, ms, gain, sharp, gap=0):
        self.segments.append(dict(duration=float(ms), gap=float(gap), gain=g(gain), sharp=g(sharp), type="continuous"))
    def tap(self, gain, sharp, gap):
        self.segments.append(dict(duration=30.0, gap=float(gap), gain=g(gain), sharp=g(sharp), type="transient"))
    def rest(self, ms):
        if self.segments: self.segments[-1]["gap"] += float(ms)
    def ramp(self, steps, step_ms, g0, g1, sharp, gap=0):
        for i in range(steps):
            t = i / max(1, steps - 1)
            self.cont(step_ms, g0 + (g1 - g0) * t, sharp, gap)
    def swell(self, up_ms, hold_ms, down_ms, peak, sharp, steps=6):
        self.ramp(steps, up_ms / steps, peak * 0.15, peak, sharp)
        if hold_ms: self.cont(hold_ms, peak, sharp)
        self.ramp(steps, down_ms / steps, peak, peak * 0.1, sharp)
    def total_ms(self):
        return sum(s["duration"] + s["gap"] for s in self.segments)

def g(x):
    return round(min(1.0, max(0.0, x)), 3)

def finish(pid, name, en, ja, score, fade_out=1500):
    peak = max(s["gain"] for s in score.segments)
    for i, s in enumerate(score.segments):
        s["gain"] = g(s["gain"] / peak)
        s["id"] = str(uuid.uuid5(NS, f"{pid}:{i}"))
    assert len(score.segments) <= 1024, (pid, len(score.segments))
    assert score.total_ms() <= 180_000, (pid, score.total_ms())
    return dict(id=pid, name=name, englishName=en, japaneseName=ja, category="节奏", description="",
                mode="basic", segments=score.segments, nodes=[], cycle=score.total_ms(), sharpness=0.5,
                loop=False, fadeIn=0, fadeOut=fade_out, premium=False, builtin=True, sourcePremium=False, updatedAt=0)

pieces = []

# m01 晨雾: slow swells that brighten, then settle.  ~90 s
s = Score()
for i in range(14):
    t = i / 13
    peak = 0.35 + 0.65 * math.sin(math.pi * min(1, t * 1.15)) if t < 0.87 else 0.5 - 0.3 * (t - 0.87) / 0.13
    s.swell(2200, 600, 2600, max(0.15, peak), 0.12 + 0.1 * t)
    s.rest(900 - 300 * t)
pieces.append(finish("m01", "晨雾", "Morning Mist", "朝霧", s))

# m02 心跳: lub-dub at 60 bpm easing to 48 bpm, fading at the end.  ~90 s
s = Score()
elapsed = 0
while elapsed < 88_000:
    t = elapsed / 88_000
    bpm = 60 - 12 * t
    beat = 60_000 / bpm
    amp = 1.0 if t < 0.8 else 1.0 - (t - 0.8) / 0.2 * 0.7
    s.tap(amp, 0.35, 110)
    s.tap(amp * 0.65, 0.2, beat - 170)
    elapsed += beat
pieces.append(finish("m02", "心跳", "Heartbeat", "鼓動", s))

# m03 雨阶: scattered drops thicken into a patter and thin out again.  ~75 s
s = Score()
rng = random.Random(3)
elapsed = 0
while elapsed < 74_000:
    t = elapsed / 74_000
    density = 0.15 + 0.85 * math.sin(math.pi * t) ** 1.4
    gap = max(70, rng.uniform(140, 900) * (1.15 - density))
    s.tap(0.4 + 0.6 * density * rng.uniform(0.7, 1), rng.uniform(0.6, 1.0), gap)
    elapsed += 30 + gap
pieces.append(finish("m03", "雨阶", "Rain Steps", "雨音", s))

# m04 潮汐: long waves that grow, crest, and recede.  ~120 s
s = Score()
for i in range(10):
    t = i / 9
    peak = 0.3 + 0.7 * math.sin(math.pi * t) ** 0.8
    s.swell(3200, 1200, 4200, peak, 0.08 + 0.12 * peak, steps=8)
    s.rest(2600 - 800 * math.sin(math.pi * t))
pieces.append(finish("m04", "潮汐", "Tide", "潮騒", s, fade_out=3000))

# m05 塔布拉: teental (16 beats) at 96 bpm, eight cycles, each a little more present.  ~80 s
s = Score()
beat = 60_000 / 96
accent = {0: (1.0, 0.75), 4: (0.8, 0.6), 8: (0.35, 0.3), 12: (0.8, 0.6)}  # sam, tali, khali, tali
for cycle in range(8):
    lift = 0.7 + 0.3 * cycle / 7
    for b in range(16):
        gain, sharp = accent.get(b, (0.5, 0.5))
        if b % 2 == 1 and cycle >= 4:  # extra off-beats once the groove is established
            s.tap(gain * lift * 0.9, sharp, beat / 2 - 30)
            s.tap(0.3 * lift, 0.8, beat / 2 - 30)
        else:
            s.tap(gain * lift, sharp, beat - 30)
pieces.append(finish("m05", "塔布拉", "Tabla", "タブラ", s, fade_out=800))

# m06 余烬: a warm low glow with crackles; the glow slowly cools.  ~90 s
s = Score()
rng = random.Random(6)
elapsed = 0
while elapsed < 88_000:
    t = elapsed / 88_000
    glow = 0.55 * (1 - t) + 0.1
    hold = rng.uniform(900, 2200)
    s.cont(hold, glow, 0.08)
    elapsed += hold
    for _ in range(rng.randint(1, 3)):
        gap = rng.uniform(90, 420)
        s.tap(rng.uniform(0.6, 1.0) * (1 - 0.5 * t) + 0.2, 1.0, gap)
        elapsed += 30 + gap
pieces.append(finish("m06", "余烬", "Ember", "残り火", s, fade_out=2500))

# m07 回廊: an unhurried walk, heel then toe, with an echo every fourth step.  ~80 s
s = Score()
for step in range(44):
    t = step / 43
    s.tap(1.0, 0.45, 150)
    s.tap(0.5, 0.25, 760)
    if step % 4 == 3:
        s.cont(900, 0.32 + 0.1 * math.sin(math.pi * t), 0.05, 500)
pieces.append(finish("m07", "回廊", "Cloister", "回廊", s))

# m08 丝路: a rocking long-short-short gait whose breath rises and falls.  ~100 s
s = Score()
for bar in range(50):
    t = bar / 49
    breath = 0.55 + 0.45 * math.sin(math.pi * t) * (0.6 + 0.4 * math.sin(2 * math.pi * t * 3))
    s.cont(520, breath, 0.18, 120)
    s.cont(240, breath * 0.6, 0.3, 90)
    s.cont(240, breath * 0.75, 0.3, 240)
pieces.append(finish("m08", "丝路", "Silk Road", "絲路", s, fade_out=2000))

# m09 螺旋: pulses that quicken into a spin, then unwind.  ~70 s
s = Score()
n = 110
for i in range(n):
    t = i / (n - 1)
    speed = math.sin(math.pi * t) ** 2
    gap = 1100 - 960 * speed
    s.tap(0.45 + 0.55 * speed, 0.4 + 0.5 * speed, gap)
pieces.append(finish("m09", "螺旋", "Spiral", "螺旋", s, fade_out=600))

# m10 深眠: breathing waves, four in / six out, sinking to stillness.  ~120 s
s = Score()
for i in range(11):
    t = i / 10
    peak = 0.9 * (1 - t) ** 1.3 + 0.08
    s.ramp(8, 4000 / 8, peak * 0.1, peak, 0.06)
    s.ramp(10, 6000 / 10, peak, peak * 0.05, 0.06)
    s.rest(800)
pieces.append(finish("m10", "深眠", "Deep Sleep", "深い眠り", s, fade_out=5000))

# m11 雷云: rumbles that gather, a few cracks, then rain.  ~60 s
s = Score()
rng = random.Random(11)
for i in range(7):
    t = i / 6
    s.ramp(5, 320, 0.2, 0.55 + 0.45 * t, 0.0)
    s.cont(600, 0.55 + 0.45 * t, 0.02, 350)
    if i in (2, 4, 5):
        s.tap(1.0, 1.0, 180)
        s.tap(0.8, 0.9, 900)
    s.rest(600 + 600 * (1 - t))
for _ in range(80):
    s.tap(rng.uniform(0.45, 0.85), rng.uniform(0.6, 0.95), rng.uniform(120, 420))
pieces.append(finish("m11", "雷云", "Thunder", "雷雲", s))

# m12 莲开: petals opening one by one, a bloom at the centre, then calm.  ~90 s
s = Score()
for layer in range(1, 7):
    for petal in range(layer):
        s.swell(700, 200, 900, 0.45 + 0.09 * layer, 0.2 + 0.05 * layer, steps=4)
        s.tap(0.6 + 0.07 * layer, 0.7, 260)
    s.rest(1200)
s.swell(2500, 1500, 3000, 1.0, 0.3, steps=8)
s.rest(1500)
for i in range(6):
    s.swell(1200, 300, 1800, 0.5 - 0.06 * i, 0.15, steps=4)
    s.rest(900)
pieces.append(finish("m12", "莲开", "Lotus", "蓮", s, fade_out=2500))

OUT.write_text(json.dumps(pieces, indent=2, ensure_ascii=False) + "\n")
for p in pieces:
    print(p["id"], p["name"], p["englishName"], "%.0fs" % (p["cycle"] / 1000), len(p["segments"]), "segments")
