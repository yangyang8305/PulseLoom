#!/usr/bin/env python3
"""Original bundled music for Pulse Loom, synthesized deterministically with numpy.

Eight short pieces in different styles (lo-fi beat, piano ballad, tabla groove, synth pulse,
waltz, bossa, ambient drift, drumline). Every part is generated here: no recordings, no samples,
no downloads. Output: App/Resources/Track-<id>.m4a (AAC) plus App/Resources/tracks.json.

Usage: python3 Scripts/compose-music.py [--wav-dir DIR] [--only t01,t02]
"""
import argparse, json, math, os, random, shutil, subprocess, sys, tempfile, wave
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "App/Resources"
SR = 44100
TAU = 2 * math.pi


# ---------------------------------------------------------------- building blocks
def midi(n):
    return 440.0 * 2 ** ((n - 69) / 12)


NOTE = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def pitch(name):
    """'C4', 'Db3', 'F#5' -> midi number."""
    letter, rest = name[0], name[1:]
    acc = 0
    while rest and rest[0] in "#b":
        acc += 1 if rest[0] == "#" else -1
        rest = rest[1:]
    return 12 * (int(rest) + 1) + NOTE[letter] + acc


def seconds(n):
    return np.arange(n) / SR


def expdecay(n, rate):
    return np.exp(-seconds(n) * rate)


def adsr(n, a=0.01, d=0.1, s=0.7, r=0.2):
    t = seconds(n)
    env = np.ones(n)
    na, nd, nr = int(a * SR), int(d * SR), int(r * SR)
    if na:
        env[:na] = np.linspace(0, 1, na)
    if nd:
        env[na:na + nd] = np.linspace(1, s, nd)[: max(0, n - na)]
    env[na + nd:] = s
    if nr and nr < n:
        env[-nr:] *= np.linspace(1, 0, nr)
    return env


def sine(f, n, phase=0.0):
    return np.sin(TAU * f * seconds(n) + phase)


def harmonics(f, n, amps, rolloff=1.0, detune=0.0):
    """Additive partials; amps[k] scales harmonic k+1. Partials above Nyquist are dropped."""
    out = np.zeros(n)
    t = seconds(n)
    for k, a in enumerate(amps):
        fk = f * (k + 1) * (1 + detune * k)
        if fk > SR * 0.45:
            break
        out += a / ((k + 1) ** rolloff) * np.sin(TAU * fk * t)
    return out


def saw(f, n, parts=24):
    return harmonics(f, n, [1.0] * parts, rolloff=1.0) * 0.6


def square(f, n, parts=16):
    return harmonics(f, n, [1.0 if k % 2 == 0 else 0.0 for k in range(parts)], rolloff=1.0) * 0.8


def noise(n, rng):
    return rng.uniform(-1, 1, n)


def lowpass(x, cutoff):
    """FFT brick-wall with a gentle shoulder; fine for shaping notes and noise."""
    n = len(x)
    spec = np.fft.rfft(x)
    freqs = np.fft.rfftfreq(n, 1 / SR)
    gain = 1 / (1 + (freqs / max(20.0, cutoff)) ** 4)
    return np.fft.irfft(spec * gain, n)


def highpass(x, cutoff):
    return x - lowpass(x, cutoff)


def pluck(f, n, rng, bright=0.5, decay=0.996):
    """Karplus-Strong string, computed one period at a time."""
    L = max(2, int(SR / f))
    buf = rng.uniform(-1, 1, L)
    buf = lowpass(buf, 800 + 6000 * bright)
    out = np.zeros(n + 2 * L)
    out[:L] = buf
    prev, prevprev = buf, np.zeros(L)
    i = L
    while i < n + L:
        shifted = np.concatenate(([prevprev[-1]], prev[:-1]))
        cur = decay * 0.5 * (prev + shifted)
        out[i:i + L] = cur[: len(out) - i]
        prevprev, prev = prev, cur
        i += L
    return out[:n]


def epiano(f, n, vel=1.0):
    """Two-operator FM electric piano."""
    t = seconds(n)
    idx = (1.2 + 1.5 * vel) * expdecay(n, 6)
    mod = np.sin(TAU * f * 14 * t) * idx * 0.02 + np.sin(TAU * f * 1.0 * t) * idx
    car = np.sin(TAU * f * t + mod)
    body = harmonics(f, n, [0.0, 0.25, 0.0, 0.08]) * expdecay(n, 9)
    return (car * expdecay(n, 2.2) + body) * adsr(n, 0.004, 0.2, 0.9, 0.25)


def piano(f, n, rng, vel=0.8):
    amps = [1.0, 0.55, 0.3, 0.2, 0.12, 0.08, 0.05, 0.03]
    rate = 1.6 + f / 220
    tone = harmonics(f, n, amps, rolloff=1.1, detune=0.0004) * expdecay(n, rate)
    hammer = lowpass(noise(min(n, int(0.02 * SR)), rng), 3000) * np.linspace(1, 0, min(n, int(0.02 * SR))) * 0.25
    out = tone * adsr(n, 0.003, 0.05, 1.0, 0.3)
    out[: len(hammer)] += hammer * vel
    return out * (0.6 + 0.4 * vel)


def pad(f, n, cutoff=1800):
    t = seconds(n)
    out = np.zeros(n)
    for det in (-0.6, 0.0, 0.7):
        out += saw(f * 2 ** (det / 1200), n, parts=14)
    out += sine(f / 2, n) * 0.4
    out = lowpass(out, cutoff)
    return out * adsr(n, 0.5, 0.3, 0.9, 0.9) * 0.3


def strings(f, n):
    t = seconds(n)
    vib = 1 + 0.004 * np.sin(TAU * 5.2 * t) * np.minimum(1, t / 0.8)
    out = np.zeros(n)
    for det in (-0.4, 0.5):
        out += harmonics(f * 2 ** (det / 1200) * vib[0], n, [1, 0.7, 0.5, 0.35, 0.25, 0.18, 0.12, 0.08], rolloff=0.9)
    return lowpass(out, 3200) * adsr(n, 0.35, 0.2, 0.9, 0.6) * 0.25


def bell(f, n):
    out = np.zeros(n)
    for ratio, amp, rate in ((1.0, 1.0, 1.8), (2.76, 0.5, 3.2), (5.40, 0.25, 5.0), (8.93, 0.12, 7.5)):
        if f * ratio < SR * 0.45:
            out += amp * sine(f * ratio, n) * expdecay(n, rate)
    return out * adsr(n, 0.002, 0.1, 1.0, 0.2) * 0.5


def musicbox(f, n):
    out = sine(f, n) * expdecay(n, 3.5) + 0.35 * sine(f * 4, n) * expdecay(n, 9) + 0.15 * sine(f * 6.1, n) * expdecay(n, 14)
    return out * adsr(n, 0.001, 0.05, 1.0, 0.1) * 0.6


def flute(f, n, rng):
    t = seconds(n)
    vib = f * (1 + 0.006 * np.sin(TAU * 5.0 * t) * np.minimum(1, t / 0.5))
    phase = np.cumsum(TAU * vib / SR)
    tone = np.sin(phase) + 0.25 * np.sin(2 * phase) + 0.08 * np.sin(3 * phase)
    breath = lowpass(noise(n, rng), 2500) * 0.04
    return (tone + breath) * adsr(n, 0.06, 0.1, 0.85, 0.15) * 0.45


def sitar(f, n, rng):
    """Bright pluck with a buzzing bridge and sympathetic shimmer."""
    core = pluck(f, n, rng, bright=0.9, decay=0.9975)
    buzz = np.sign(core) * np.abs(core) ** 0.6 * 0.25
    shimmer = sine(f * 2, n) * expdecay(n, 4) * 0.08 + sine(f * 3.01, n) * expdecay(n, 6) * 0.04
    return (core + buzz + shimmer) * 0.5


def bass(f, n, kind="sine"):
    if kind == "sine":
        tone = sine(f, n) + 0.3 * sine(f * 2, n) * expdecay(n, 5)
        return tone * adsr(n, 0.005, 0.1, 0.8, 0.08) * 0.8
    if kind == "synth":
        tone = lowpass(saw(f, n, parts=12) + square(f / 2, n, parts=6) * 0.4, 500 + 900 * expdecay(n, 8)[0])
        return tone * adsr(n, 0.004, 0.08, 0.7, 0.06) * 0.9
    return pluck(f, n, np.random.default_rng(int(f)), bright=0.25, decay=0.998) * adsr(n, 0.002, 0.05, 1.0, 0.1)


# drums ------------------------------------------------------------------------
def kick(n, rng, low=48, high=160, punch=1.0):
    t = seconds(n)
    f = low + (high - low) * np.exp(-t * 40)
    phase = np.cumsum(TAU * f / SR)
    body = np.sin(phase) * expdecay(n, 7)
    click = highpass(noise(n, rng), 1500) * expdecay(n, 250) * 0.5 * punch
    return np.tanh((body * 1.4 + click) * 1.3) * 0.9


def snare(n, rng, tone=190):
    body = sine(tone, n) * expdecay(n, 28) * 0.5
    rattle = highpass(noise(n, rng), 1800) * expdecay(n, 18) * 0.8
    return (body + rattle) * 0.8


def hat(n, rng, open_=False):
    x = highpass(noise(n, rng), 7000)
    return x * expdecay(n, 12 if open_ else 55) * 0.35


def shaker(n, rng):
    x = highpass(noise(n, rng), 4500)
    return x * np.minimum(1, seconds(n) / 0.015) * expdecay(n, 45) * 0.25


def clap(n, rng):
    out = np.zeros(n)
    for k in range(3):
        off = int(0.011 * k * SR)
        burst = highpass(noise(n - off, rng), 1200) * expdecay(n - off, 60 if k < 2 else 14)
        out[off:] += burst
    return out * 0.35


def rim(n, rng):
    return (sine(820, n) * expdecay(n, 90) + highpass(noise(n, rng), 3000) * expdecay(n, 180)) * 0.35


def bayan(n, f0=70, bend=1.5):
    """Tabla's bass drum: a pitch that rises as the heel presses."""
    t = seconds(n)
    f = f0 * (1 + (bend - 1) * np.minimum(1, t / 0.25))
    phase = np.cumsum(TAU * f / SR)
    return np.sin(phase) * expdecay(n, 6) * adsr(n, 0.002, 0.05, 1.0, 0.1) * 0.9


def dayan(n, rng, f=420, kind="na"):
    if kind == "na":
        tone = sine(f, n) * expdecay(n, 14) + 0.4 * sine(f * 2.0, n) * expdecay(n, 22)
        strike = highpass(noise(n, rng), 2500) * expdecay(n, 140) * 0.5
        return (tone + strike) * 0.55
    if kind == "tin":
        tone = sine(f * 1.5, n) * expdecay(n, 9) + 0.3 * sine(f * 3.0, n) * expdecay(n, 16)
        return tone * 0.5
    # "te": closed slap
    return highpass(noise(n, rng), 1500) * expdecay(n, 90) * 0.5


def taiko(n, rng, f=92):
    t = seconds(n)
    body = sine(f, n) * expdecay(n, 4.5) + 0.3 * sine(f * 1.5, n) * expdecay(n, 9)
    skin = lowpass(noise(n, rng), 1800) * expdecay(n, 60) * 0.7
    return np.tanh((body + skin) * 1.5) * 0.9


# effects ------------------------------------------------------------------------
def reverb_ir(rng, seconds_=1.6, bright=0.5):
    n = int(seconds_ * SR)
    tail = noise(n, rng) * np.exp(-seconds(n) * (3.2 / seconds_))
    tail = lowpass(tail, 2500 + 5000 * bright)
    early = np.zeros(n)
    for d, g in ((0.011, 0.6), (0.019, 0.45), (0.029, 0.35), (0.043, 0.25)):
        early[int(d * SR)] += g
    ir = early + tail * 0.35
    return ir / np.max(np.abs(ir))


def convolve(x, ir):
    n = len(x) + len(ir) - 1
    y = np.fft.irfft(np.fft.rfft(x, n) * np.fft.rfft(ir, n), n)
    return y[: len(x)]


def soft_limit(x, drive=1.15):
    return np.tanh(x * drive) / math.tanh(drive)


# ---------------------------------------------------------------- song canvas
class Song:
    def __init__(self, tid, bpm, length_s, seed):
        self.tid, self.bpm = tid, bpm
        self.n = int(length_s * SR)
        self.rng = np.random.default_rng(seed)
        self.tracks = {}  # name -> (L, R, reverb send)

    def beat(self, b):
        return b * 60.0 / self.bpm

    def track(self, name, send=0.0):
        if name not in self.tracks:
            self.tracks[name] = [np.zeros(self.n), np.zeros(self.n), send]
        return self.tracks[name]

    def add(self, name, sig, at_s, gain=1.0, pan=0.0, send=None):
        i = int(at_s * SR)
        if i >= self.n or i < 0:
            return
        sig = sig[: self.n - i]
        tr = self.track(name)
        if send is not None:
            tr[2] = send
        left = math.cos((pan + 1) * math.pi / 4)
        right = math.sin((pan + 1) * math.pi / 4)
        tr[0][i:i + len(sig)] += sig * gain * left
        tr[1][i:i + len(sig)] += sig * gain * right

    def mix(self, master=0.9, fade_in=0.05, fade_out=2.5, reverb_bright=0.5, reverb_len=1.6):
        L = np.zeros(self.n)
        R = np.zeros(self.n)
        irL = reverb_ir(np.random.default_rng(11), reverb_len, reverb_bright)
        irR = reverb_ir(np.random.default_rng(23), reverb_len, reverb_bright)
        sendL = np.zeros(self.n)
        sendR = np.zeros(self.n)
        for name, (l, r, send) in self.tracks.items():
            L += l
            R += r
            if send > 0:
                sendL += l * send
                sendR += r * send
        if np.any(sendL):
            L += convolve(sendL, irL)
            R += convolve(sendR, irR)
        peak = max(np.max(np.abs(L)), np.max(np.abs(R)), 1e-6)
        L, R = L / peak, R / peak
        L, R = soft_limit(L * 1.1), soft_limit(R * 1.1)
        env = np.ones(self.n)
        fi, fo = int(fade_in * SR), int(fade_out * SR)
        env[:fi] = np.linspace(0, 1, fi)
        env[-fo:] *= np.linspace(1, 0, fo) ** 1.5
        peak = max(np.max(np.abs(L)), np.max(np.abs(R)), 1e-6)
        return L * env * master / peak, R * env * master / peak


def write_wav(path, L, R):
    data = np.stack([L, R], axis=1)
    pcm = (np.clip(data, -1, 1) * 32767).astype("<i2")
    with wave.open(str(path), "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def n_of(sec):
    return max(1, int(sec * SR))


def chord_notes(root, kind):
    base = pitch(root)
    shapes = {"maj": [0, 4, 7], "min": [0, 3, 7], "maj7": [0, 4, 7, 11], "min7": [0, 3, 7, 10], "dom7": [0, 4, 7, 10],
              "sus2": [0, 2, 7], "add9": [0, 4, 7, 14], "min9": [0, 3, 7, 10, 14], "maj9": [0, 4, 7, 11, 14]}
    return [base + s for s in shapes[kind]]


# ---------------------------------------------------------------- the pieces
def t01_slow_walk():
    """Lo-fi hip hop: swung drums, electric piano, round bass. 76 bpm, ~84 s."""
    s = Song("t01", 76, 84, 101)
    rng = s.rng
    prog = [("D3", "min9"), ("G3", "min7"), ("Bb3", "maj7"), ("A3", "dom7")]
    bar = s.beat(4)
    bars = int(84 / bar)
    swing = 0.09
    for b in range(bars):
        t0 = b * bar
        root, kind = prog[b % 4]
        if b >= 1:  # drums enter in bar 2
            s.add("kick", kick(n_of(0.5), rng), t0, 1.1)
            s.add("kick", kick(n_of(0.5), rng), t0 + s.beat(2.5 + (0.0 if b % 2 else 0.25)), 0.9)
            s.add("snare", snare(n_of(0.35), rng), t0 + s.beat(1), 0.95, 0.05, send=0.25)
            s.add("snare", snare(n_of(0.35), rng), t0 + s.beat(3), 0.95, 0.05)
            for e in range(8):
                off = s.beat(e * 0.5) + (s.beat(swing) if e % 2 else 0)
                s.add("hat", hat(n_of(0.12), rng, open_=(e == 7 and b % 4 == 3)), t0 + off, 0.3 if e % 2 == 0 else 0.18, 0.3)
            if b % 4 == 3:
                s.add("snare", snare(n_of(0.2), rng, 240), t0 + s.beat(3.75), 0.4, -0.1)
        # electric piano: chord on 1 and the "and" of 2, with a 9th sprinkle
        notes = chord_notes(root, kind)
        for hit, vel, dur in ((0.0, 0.9, 1.6), (1.5, 0.6, 1.0), (3.0, 0.5, 0.9)):
            for k, m in enumerate(notes):
                s.add("ep", epiano(midi(m), n_of(dur), vel), t0 + s.beat(hit) + 0.004 * k, 0.11 * vel, 0.2 - 0.1 * k, send=0.3)
        # bass: root, octave, fifth walk
        line = [(0, notes[0] - 12, 1.2), (1.5, notes[0] - 12, 0.4), (2, notes[0] - 5, 0.8), (3, notes[0] - 12, 0.9)]
        for at, m, dur in line:
            s.add("bass", bass(midi(m), n_of(dur * 0.7), "sine"), t0 + s.beat(at), 0.5, 0.0)
        # melody fragment every other bar
        if b % 2 == 1 and b >= 3:
            mel = [notes[1] + 12, notes[2] + 12, notes[1] + 12, notes[0] + 12] if b % 4 == 1 else [notes[2] + 12, notes[1] + 12, notes[3 if len(notes) > 3 else 0] + 12]
            for k, m in enumerate(mel):
                s.add("lead", epiano(midi(m), n_of(0.7), 0.7), t0 + s.beat(2 + 0.5 * k), 0.16, -0.25, send=0.4)
    # vinyl-ish texture
    s.add("tex", lowpass(noise(s.n, rng), 1200) * 0.006, 0)
    return s.mix(reverb_bright=0.35)


def t02_evening_lamp():
    """Piano ballad with strings: 66 bpm, ~92 s."""
    s = Song("t02", 66, 92, 202)
    rng = s.rng
    prog = [("C4", "maj9"), ("A3", "min7"), ("F3", "maj7"), ("G3", "sus2"), ("C4", "maj9"), ("E3", "min7"), ("F3", "maj7"), ("G3", "dom7")]
    bar = s.beat(4)
    bars = int(92 / bar)
    melody = [[7, 9, 11, 12], [9, 7, 4, 2], [5, 7, 9, 4], [2, 4, 7, 7]]
    for b in range(bars):
        t0 = b * bar
        root, kind = prog[b % len(prog)]
        notes = chord_notes(root, kind)
        # left hand: root low, then broken chord
        s.add("piano", piano(midi(notes[0] - 12), n_of(2.0), rng, 0.8), t0, 0.5, -0.3, send=0.35)
        for k, at in enumerate((0.5, 1.0, 1.5, 2.5, 3.0, 3.5)):
            m = notes[(k % (len(notes) - 1)) + 1]
            s.add("piano", piano(midi(m), n_of(1.2), rng, 0.45), t0 + s.beat(at), 0.3, -0.15)
        # right hand melody from bar 3
        if b >= 2:
            line = melody[(b - 2) % 4]
            for k, deg in enumerate(line):
                m = pitch("C5") + deg
                dur = 1.0 if k < 3 else 1.4
                s.add("piano", piano(midi(m), n_of(dur), rng, 0.7), t0 + s.beat(k), 0.5, 0.25)
        # strings from bar 5
        if b >= 4:
            for k, m in enumerate(notes[:3]):
                s.add("strings", strings(midi(m + 12), n_of(bar)), t0 + 0.02 * k, 0.11, 0.4 - 0.4 * k, send=0.5)
        # soft brushed pulse
        if b >= 6:
            s.add("brush", shaker(n_of(0.3), rng), t0 + s.beat(1), 0.5, 0.4)
            s.add("brush", shaker(n_of(0.3), rng), t0 + s.beat(3), 0.5, 0.4)
            s.add("kick", kick(n_of(0.5), rng, 40, 90, 0.2), t0, 0.6)
    return s.mix(reverb_bright=0.55, reverb_len=2.2, fade_out=4)


def t03_tabla_night():
    """Tanpura drone, teental tabla cycle, sitar melody in Bhairav. 104 bpm, ~88 s."""
    s = Song("t03", 104, 88, 303)
    rng = s.rng
    sa = pitch("D3")
    scale = [0, 1, 4, 5, 7, 8, 11, 12, 13, 16]  # Bhairav: S r G m P d N S'
    # tanpura: Pa Sa Sa Sa(low), plucked continuously
    cycle = s.beat(4)
    t = 0.0
    k = 0
    while t < 88:
        m = [sa + 7, sa + 12, sa + 12, sa][k % 4]
        s.add("tanpura", pluck(midi(m), n_of(2.4), rng, bright=0.75, decay=0.9993), t, 0.07, -0.4 + 0.2 * (k % 2), send=0.4)
        t += cycle / 4
        k += 1
    # teental (16 matras): dha dhin dhin dha | dha dhin dhin dha | dha tin tin ta | ta dhin dhin dha
    bols = ["dha", "dhin", "dhin", "dha", "dha", "dhin", "dhin", "dha", "dha", "tin", "tin", "ta", "ta", "dhin", "dhin", "dha"]
    matra = s.beat(1) / 2
    cyc = 0
    t = s.beat(4)  # drone alone for one bar
    while t < 86:
        for i, bol in enumerate(bols):
            at = t + i * matra
            dense = cyc >= 2
            if bol in ("dha", "dhin"):
                s.add("bayan", bayan(n_of(0.45), 68, 1.6 if bol == "dha" else 1.25), at, 1.1)
            if bol in ("dha", "ta"):
                s.add("dayan", dayan(n_of(0.3), rng, 440, "na"), at, 0.8, 0.25)
            elif bol == "dhin":
                s.add("dayan", dayan(n_of(0.25), rng, 440, "tin"), at, 0.55, 0.25)
            elif bol == "tin":
                s.add("dayan", dayan(n_of(0.3), rng, 440, "tin"), at, 0.75, 0.25)
            if dense and i % 2 == 1:
                s.add("dayan", dayan(n_of(0.12), rng, 440, "te"), at + matra / 2, 0.3, 0.3)
        cyc += 1
        t += 16 * matra
    # sitar: alap-like phrases then a gat
    phrase_bank = [[0, 1, 0, 4, 5, 4, 1, 0], [4, 5, 7, 8, 7, 5, 4, 5], [7, 8, 11, 12, 11, 8, 7, 5], [12, 13, 12, 11, 8, 7, 5, 4]]
    t = s.beat(4)
    p = 0
    while t < 82:
        phrase = phrase_bank[p % 4]
        step = matra * (2 if t < s.beat(24) else 1)
        for k, deg in enumerate(phrase):
            m = sa + 12 + scale[deg % len(scale)] + (12 if deg >= 12 else 0) - (12 if deg >= 12 else 0)
            m = sa + 12 + deg if deg in scale else sa + 12 + scale[min(len(scale) - 1, deg)]
            dur = step * (1.9 if k == len(phrase) - 1 else 1.1)
            s.add("sitar", sitar(midi(m), n_of(dur), rng), t + k * step, 0.3, -0.1, send=0.45)
            if k % 4 == 0:
                s.add("sitar", sitar(midi(sa + 12), n_of(step), rng), t + k * step + step * 0.5, 0.1, 0.1)
        t += len(phrase) * step + step
        p += 1
    return s.mix(reverb_bright=0.5, reverb_len=1.9, fade_out=3)


def t04_pulse():
    """Synth pulse: arpeggio, four-on-the-floor, claps. 112 bpm, ~86 s."""
    s = Song("t04", 112, 86, 404)
    rng = s.rng
    prog = [("A2", "min"), ("F2", "maj"), ("C3", "maj"), ("G2", "maj")]
    bar = s.beat(4)
    bars = int(86 / bar)
    for b in range(bars):
        t0 = b * bar
        root, kind = prog[b % 4]
        notes = chord_notes(root, kind)
        intro = b < 4
        outro = b >= bars - 3
        # arpeggio 16ths, rising then falling
        arp = [notes[0] + 12, notes[1] + 12, notes[2] + 12, notes[0] + 24, notes[2] + 12, notes[1] + 12]
        cutoff = 900 + 2600 * (0.5 + 0.5 * math.sin(math.pi * b / bars))
        for e in range(16):
            m = arp[e % len(arp)]
            sig = lowpass(saw(midi(m), n_of(0.22), parts=18), cutoff) * adsr(n_of(0.22), 0.003, 0.08, 0.5, 0.06)
            s.add("arp", sig, t0 + s.beat(e * 0.25), 0.13 if e % 4 == 0 else 0.08, 0.35 * math.sin(e), send=0.2)
        # bass on 8ths
        for e in range(8):
            s.add("bass", bass(midi(notes[0]), n_of(0.18), "synth"), t0 + s.beat(e * 0.5), 0.45 if e % 2 == 0 else 0.28)
        # pad
        for k, m in enumerate(notes):
            s.add("pad", pad(midi(m + 12), n_of(bar + 0.3), 1400), t0, 0.12, -0.4 + 0.4 * k, send=0.5)
        if not intro and not outro:
            for e in range(4):
                s.add("kick", kick(n_of(0.45), rng, 45, 170, 1.2), t0 + s.beat(e), 1.4)
            s.add("clap", clap(n_of(0.3), rng), t0 + s.beat(1), 1.0, 0.1, send=0.3)
            s.add("clap", clap(n_of(0.3), rng), t0 + s.beat(3), 1.0, 0.1)
            for e in range(8):
                s.add("hat", hat(n_of(0.1), rng, open_=(e % 2 == 1)), t0 + s.beat(e * 0.5 + 0.25), 0.18, -0.3)
        elif intro and b >= 2:
            for e in range(4):
                s.add("kick", kick(n_of(0.45), rng, 45, 150, 0.8), t0 + s.beat(e), 0.7)
        # lead from bar 8: long notes
        if 8 <= b < bars - 3 and b % 2 == 0:
            lead = [notes[2] + 24, notes[1] + 24, notes[0] + 24 + (2 if kind == "min" else 0)]
            for k, m in enumerate(lead):
                sig = lowpass(square(midi(m), n_of(s.beat(2.5)), parts=10) + saw(midi(m) * 1.002, n_of(s.beat(2.5)), parts=10), 2600)
                s.add("lead", sig * adsr(n_of(s.beat(2.5)), 0.05, 0.2, 0.7, 0.4), t0 + s.beat(k * 2.6), 0.09, 0.0, send=0.45)
    return s.mix(reverb_bright=0.6, reverb_len=1.4)


def t05_waltz():
    """Music-box waltz with strings: 3/4, 138 bpm, ~78 s."""
    s = Song("t05", 138, 78, 505)
    rng = s.rng
    prog = [("G3", "maj"), ("E3", "min"), ("C3", "maj"), ("D3", "dom7"), ("G3", "maj"), ("B2", "min"), ("C3", "maj"), ("D3", "dom7")]
    bar = s.beat(3)
    bars = int(78 / bar)
    tune = [[7, 11, 14], [12, 11, 9], [7, 4, 7], [9, 7, 5], [7, 11, 14], [16, 14, 11], [12, 9, 7], [9, 7, 7]]
    for b in range(bars):
        t0 = b * bar
        root, kind = prog[b % 8]
        notes = chord_notes(root, kind)
        # oom-pah-pah
        s.add("bassbox", musicbox(midi(notes[0] - 12), n_of(0.8)), t0, 0.7, -0.2)
        s.add("bassbox", bass(midi(notes[0] - 24), n_of(0.5), "sine"), t0, 0.5)
        for beat in (1, 2):
            for k, m in enumerate(notes[:3]):
                s.add("chordbox", musicbox(midi(m), n_of(0.5)), t0 + s.beat(beat) + 0.003 * k, 0.25, 0.1 + 0.1 * k)
        # melody
        if b >= 2:
            line = tune[b % 8]
            for k, deg in enumerate(line):
                m = pitch("G5") + deg
                s.add("melody", musicbox(midi(m), n_of(0.9 if k < 2 else 1.1)), t0 + s.beat(k), 0.55, 0.0, send=0.5)
            if b % 4 == 3:
                s.add("melody", musicbox(midi(pitch("G5") + line[-1] + 2), n_of(0.5)), t0 + s.beat(2.5), 0.3, 0.0)
        if b >= 8:
            for k, m in enumerate(notes[:3]):
                s.add("strings", strings(midi(m + 12), n_of(bar)), t0 + 0.03 * k, 0.07, 0.5 - 0.5 * k, send=0.5)
        if 4 <= b:
            s.add("perc", shaker(n_of(0.2), rng), t0 + s.beat(1), 0.4, 0.45)
            s.add("perc", shaker(n_of(0.2), rng), t0 + s.beat(2), 0.3, 0.45)
    return s.mix(reverb_bright=0.7, reverb_len=1.8, fade_out=3)


def t06_seaside_bossa():
    """Bossa nova: nylon guitar, bass, rim and shaker, flute melody. 118 bpm, ~86 s."""
    s = Song("t06", 118, 86, 606)
    rng = s.rng
    prog = [("F3", "maj7"), ("G3", "dom7"), ("E3", "min7"), ("A3", "dom7"), ("D3", "min7"), ("G3", "dom7"), ("C3", "maj7"), ("C3", "maj7")]
    bar = s.beat(4)
    bars = int(86 / bar)
    melody = [[9, 7, 5, 7], [7, 5, 4, 2], [4, 5, 7, 4], [2, 0, 2, 4]]
    for b in range(bars):
        t0 = b * bar
        root, kind = prog[b % 8]
        notes = chord_notes(root, kind)
        # bass: root and fifth, bossa pattern
        for at, m in ((0, notes[0] - 12), (1.5, notes[0] - 12 + 7), (2, notes[0] - 12), (3.5, notes[0] - 12 + 7)):
            s.add("bass", bass(midi(m), n_of(0.6), "pluck"), t0 + s.beat(at), 0.8)
        # guitar comping: chord on the "and"s
        for at in (0.5, 1.5, 2.25, 3.0, 3.5):
            for k, m in enumerate(notes):
                s.add("guitar", pluck(midi(m), n_of(0.5), rng, bright=0.45, decay=0.995), t0 + s.beat(at) + 0.012 * k, 0.26, -0.3 + 0.15 * k, send=0.3)
        # percussion
        if b >= 1:
            for at in (0, 1.5, 2.5, 3.0):
                s.add("rim", rim(n_of(0.1), rng), t0 + s.beat(at), 0.6, 0.3)
            for e in range(8):
                s.add("shaker", shaker(n_of(0.15), rng), t0 + s.beat(e * 0.5), 0.45 if e % 2 else 0.3, 0.4)
            s.add("kick", kick(n_of(0.4), rng, 50, 110, 0.4), t0, 0.5)
            s.add("kick", kick(n_of(0.4), rng, 50, 110, 0.4), t0 + s.beat(2.5), 0.4)
        # flute melody from bar 5
        if b >= 4 and (b % 8) in (0, 1, 2, 3, 4, 5):
            line = melody[b % 4]
            for k, deg in enumerate(line):
                m = pitch("C5") + deg
                s.add("flute", flute(midi(m), n_of(0.8 if k < 3 else 1.3), rng), t0 + s.beat(0.5 + k * 0.9), 0.45, 0.1, send=0.45)
    return s.mix(reverb_bright=0.55, reverb_len=1.5)


def t07_star_drift():
    """Ambient: deep pad, slow bells, a sub pulse. 60 bpm, ~100 s."""
    s = Song("t07", 60, 100, 707)
    rng = s.rng
    prog = [("A2", "add9"), ("F2", "maj9"), ("C3", "maj9"), ("G2", "add9")]
    bar = s.beat(4)
    bars = int(100 / bar)
    for b in range(bars):
        t0 = b * bar
        root, kind = prog[(b // 2) % 4]
        notes = chord_notes(root, kind)
        if b % 2 == 0:
            for k, m in enumerate(notes):
                s.add("pad", pad(midi(m + 12), n_of(2 * bar + 1.5), 1100 + 300 * k), t0 + 0.1 * k, 0.2, -0.5 + 0.25 * k, send=0.7)
            s.add("sub", sine(midi(notes[0] - 12), n_of(2 * bar)) * adsr(n_of(2 * bar), 0.8, 0.5, 0.9, 1.5), t0, 0.25)
        # sub pulse on every beat, gentle
        for e in range(4):
            s.add("pulse", kick(n_of(0.6), rng, 38, 60, 0.0), t0 + s.beat(e), 1.0 if e == 0 else 0.6)
        # bells: sparse, from bar 3
        if b >= 2:
            picks = rng.choice(len(notes), size=2, replace=False)
            for k, idx in enumerate(picks):
                at = s.beat(rng.choice([0, 1.5, 2, 3.5]))
                s.add("bells", bell(midi(notes[idx] + 24), n_of(3.0)), t0 + at + k * 0.9, 0.3, rng.uniform(-0.6, 0.6), send=0.8)
    # slow shimmer
    s.add("air", lowpass(noise(s.n, rng), 600) * 0.02 * (0.5 + 0.5 * np.sin(TAU * 0.05 * seconds(s.n))), 0)
    return s.mix(reverb_bright=0.4, reverb_len=3.0, fade_in=1.5, fade_out=6)


def t08_drumline():
    """Taiko and snares building up, call and response. 96 bpm, ~80 s."""
    s = Song("t08", 96, 80, 808)
    rng = s.rng
    bar = s.beat(4)
    bars = int(80 / bar)
    for b in range(bars):
        t0 = b * bar
        stage = min(4, b // 4)
        # big drum
        pattern = [(0, 1.0), (2, 0.8)] if stage == 0 else [(0, 1.0), (1.5, 0.6), (2, 0.9), (3.5, 0.5)]
        for at, g in pattern:
            s.add("taiko", taiko(n_of(0.9), rng, 88), t0 + s.beat(at), g, -0.1, send=0.35)
        if stage >= 1:
            for at in (1, 3):
                s.add("snare", snare(n_of(0.3), rng, 210), t0 + s.beat(at), 0.75, 0.2, send=0.25)
            for e in range(8):
                s.add("snare", snare(n_of(0.15), rng, 260), t0 + s.beat(e * 0.5 + 0.25), 0.22, 0.3)
        if stage >= 2:
            for e in range(16):
                if e % 4 != 0:
                    s.add("tick", rim(n_of(0.08), rng), t0 + s.beat(e * 0.25), 0.4, -0.4)
            s.add("taiko2", taiko(n_of(0.6), rng, 140), t0 + s.beat(2.75), 0.5, 0.4)
        if stage >= 3:
            for at in (0.75, 1.75, 2.25, 3.75):
                s.add("taiko2", taiko(n_of(0.5), rng, 130), t0 + s.beat(at), 0.6, 0.45)
            s.add("clap", clap(n_of(0.3), rng), t0 + s.beat(3), 0.5, 0.0)
        if b % 8 == 7:  # fill
            for e in range(8):
                s.add("snare", snare(n_of(0.12), rng, 230), t0 + s.beat(2 + e * 0.25), 0.45 + 0.05 * e, 0.0)
            s.add("taiko", taiko(n_of(1.4), rng, 70), t0 + s.beat(3.75), 1.0, 0.0, send=0.5)
        # low drone pulse for body
        s.add("drone", sine(midi(pitch("D2")), n_of(bar)) * adsr(n_of(bar), 0.3, 0.2, 0.6, 0.5), t0, 0.12)
    return s.mix(reverb_bright=0.45, reverb_len=1.3, fade_out=3)


TRACKS = [
    ("t01", "慢步", "Slow Walk", "ゆっくり歩く", "lofi", t01_slow_walk),
    ("t02", "晚灯", "Evening Lamp", "夕べの灯り", "piano", t02_evening_lamp),
    ("t03", "塔布拉之夜", "Tabla Night", "タブラの夜", "tabla", t03_tabla_night),
    ("t04", "心潮", "Pulse", "パルス", "synth", t04_pulse),
    ("t05", "圆舞", "Little Waltz", "小さなワルツ", "waltz", t05_waltz),
    ("t06", "海边", "Seaside", "海辺", "bossa", t06_seaside_bossa),
    ("t07", "星河", "Star Drift", "星の流れ", "ambient", t07_star_drift),
    ("t08", "鼓阵", "Drumline", "太鼓の列", "drums", t08_drumline),
]


def encode(wav, m4a):
    subprocess.run(["afconvert", "-f", "m4af", "-d", "aac", "-b", "96000", "-s", "2", str(wav), str(m4a)], check=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--wav-dir", default=None)
    ap.add_argument("--only", default=None)
    args = ap.parse_args()
    wav_dir = Path(args.wav_dir) if args.wav_dir else Path(tempfile.mkdtemp(prefix="pulseloom-music-"))
    wav_dir.mkdir(parents=True, exist_ok=True)
    only = set(args.only.split(",")) if args.only else None
    manifest_path = OUT / "tracks.json"
    manifest = {t["id"]: t for t in json.loads(manifest_path.read_text())} if manifest_path.exists() else {}
    for tid, zh, en, ja, style, fn in TRACKS:
        if only and tid not in only:
            continue
        L, R = fn()
        wav = wav_dir / f"{tid}.wav"
        write_wav(wav, L, R)
        m4a = OUT / f"Track-{tid}.m4a"
        encode(wav, m4a)
        bpm = {"t01": 76, "t02": 66, "t03": 104, "t04": 112, "t05": 138, "t06": 118, "t07": 60, "t08": 96}[tid]
        manifest[tid] = dict(id=tid, file=f"Track-{tid}", name=zh, englishName=en, japaneseName=ja, style=style, bpm=bpm,
                             seconds=round(len(L) / SR, 1), bytes=m4a.stat().st_size)
        print(f"{tid} {en:14s} {len(L)/SR:6.1f}s  {m4a.stat().st_size/1e6:4.2f} MB", flush=True)
    ordered = [manifest[t[0]] for t in TRACKS if t[0] in manifest]
    manifest_path.write_text(json.dumps(ordered, ensure_ascii=False, indent=2) + "\n")
    print("wrote", manifest_path, "total", sum(t["bytes"] for t in ordered) / 1e6, "MB")


if __name__ == "__main__":
    main()
