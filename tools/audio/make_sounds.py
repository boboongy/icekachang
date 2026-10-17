"""Placeholder music and sound effects, synthesised from scratch (no samples, nothing to license).
Writes 16-bit mono WAVs to assets/audio/. Loops (music, rain, shave) carry a WAV 'smpl' loop
chunk, which Godot's importer reads ("Loop Mode: Detect From WAV").

Run with plain Python 3 (stdlib only):
    python tools/audio/make_sounds.py
The owner may replace any file later with a real recording of the same name.
"""
import math
import os
import random
import struct

RATE = 22050
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "assets", "audio")
TAU = 2 * math.pi


def buf(secs):
    return [0.0] * int(secs * RATE)


def write(name, s, loop=False, peak=0.9):
    m = max(1e-6, max(abs(v) for v in s))
    g = peak / m
    data = b"".join(struct.pack("<h", int(max(-1.0, min(1.0, v * g)) * 32767)) for v in s)
    fmt = struct.pack("<HHIIHH", 1, 1, RATE, RATE * 2, 2, 16)
    chunks = b"fmt " + struct.pack("<I", len(fmt)) + fmt
    chunks += b"data" + struct.pack("<I", len(data)) + data
    if loop:
        smpl = struct.pack("<9I", 0, 0, int(1e9 / RATE), 60, 0, 0, 0, 1, 0)
        smpl += struct.pack("<6I", 0, 0, 0, len(s) - 1, 0, 0)
        chunks += b"smpl" + struct.pack("<I", len(smpl)) + smpl
    with open(os.path.join(OUT, name + ".wav"), "wb") as f:
        f.write(b"RIFF" + struct.pack("<I", 4 + len(chunks)) + b"WAVE" + chunks)
    print("wrote", name, "%.2fs" % (len(s) / RATE), "loop" if loop else "")


def lowpass(s, cut):
    a = 1 - math.exp(-TAU * cut / RATE)
    y, out = 0.0, []
    for v in s:
        y += a * (v - y)
        out.append(y)
    return out


def noise(n, rng):
    return [rng.uniform(-1, 1) for _ in range(n)]


def add(dst, src, at=0, gain=1.0, wrap=False):
    n = len(dst)
    for i, v in enumerate(src):
        j = at + i
        if wrap:
            j %= n
        elif j >= n:
            break
        dst[j] += v * gain


def crossfade_loop(s, fade):
    """Fold the last `fade` samples over the start so the end runs into the start smoothly."""
    body = s[:-fade]
    for i in range(fade):
        t = i / fade
        body[i] = body[i] * t + s[len(s) - fade + i] * (1 - t)
    return body


def tone(freq, secs, decay, partials=((1, 1.0),), attack=0.004, sweep_to=None):
    out = []
    n = int(secs * RATE)
    ph = [0.0] * len(partials)
    for i in range(n):
        t = i / RATE
        f = freq if sweep_to is None else freq + (sweep_to - freq) * (i / n)
        env = min(1.0, t / attack) * math.exp(-t / decay)
        v = 0.0
        for k, (mult, amp) in enumerate(partials):
            ph[k] += TAU * f * mult / RATE
            v += math.sin(ph[k]) * amp
        out.append(v * env)
    return out


def midi(n):
    return 440.0 * 2 ** ((n - 69) / 12)


# --- music -----------------------------------------------------------------------------------

def music(rng):
    """Calm 8-bar loop, 92 bpm: soft bass, kalimba-like arpeggio, a gentle pentatonic tune and
    a whisper of shaker. C - Am - F - G, two bars each."""
    bpm = 92
    beat = 60 / bpm
    s = buf(32 * beat)
    chords = [(48, [60, 64, 67, 72]), (45, [57, 60, 64, 69]), (41, [57, 60, 65, 69]), (43, [55, 59, 62, 67])]
    pluck = ((1, 1.0), (2, 0.35), (3, 0.08))
    for bar in range(8):
        root, notes = chords[bar // 2]
        t0 = bar * 4 * beat
        for b in (0, 2):
            add(s, tone(midi(root), 1.4, 0.45, ((1, 1.0), (2, 0.25))), int((t0 + b * beat) * RATE), 0.55, wrap=True)
        for k in range(8):                       # eighth-note arpeggio, up then down
            n = notes[[0, 1, 2, 3, 2, 1, 2, 1][k]]
            add(s, tone(midi(n), 0.9, 0.22, pluck), int((t0 + k * beat / 2) * RATE), 0.22, wrap=True)
        for k in range(8):                       # shaker on the off-beats
            if k % 2:
                sh = [v * math.exp(-i / (0.02 * RATE)) for i, v in enumerate(noise(int(0.06 * RATE), rng))]
                add(s, lowpass(sh, 6000), int((t0 + k * beat / 2) * RATE), 0.05, wrap=True)
    scale = [72, 74, 76, 79, 81, 84]             # C pentatonic, one octave up
    i = 2
    t = 0.0
    while t < 32 * beat - 0.01:
        dur = beat * rng.choice((1, 1, 2, 0.5, 0.5))
        if rng.random() < 0.22:                  # rests keep it calm
            t += dur
            continue
        i = max(0, min(len(scale) - 1, i + rng.choice((-2, -1, -1, 0, 1, 1, 2))))
        note = tone(midi(scale[i]), dur + 0.6, 0.35 + dur * 0.3, ((1, 1.0), (2, 0.12)), attack=0.02)
        add(s, note, int(t * RATE), 0.2, wrap=True)
        t += dur
    write("music", s, loop=True, peak=0.6)


# --- ambience --------------------------------------------------------------------------------

def rain(rng):
    n = int(4.5 * RATE)
    hiss = lowpass(noise(n, rng), 3500)
    rumble = lowpass(noise(n, rng), 300)
    s = [h * 0.5 + r * 1.2 for h, r in zip(hiss, rumble)]
    for _ in range(140):                         # drops
        f = rng.uniform(1800, 4200)
        add(s, tone(f, 0.04, 0.008), rng.randrange(n), rng.uniform(0.05, 0.2))
    write("rain", crossfade_loop(s, int(0.5 * RATE)), loop=True, peak=0.7)


def shave(rng):
    """Ice grinding under the blade: band of noise, pulsing like the turning drum."""
    n = int(1.3 * RATE)
    nz = noise(n, rng)
    band = [a - b for a, b in zip(lowpass(nz, 5000), lowpass(nz, 900))]
    s = []
    for i, v in enumerate(band):
        t = i / RATE
        grind = 0.55 + 0.45 * abs(math.sin(TAU * 7.0 * t)) ** 0.5
        s.append(v * grind)
    write("shave", crossfade_loop(s, int(0.3 * RATE)), loop=True, peak=0.6)


# --- one-shots -------------------------------------------------------------------------------

def scoop(rng):
    s = tone(620, 0.16, 0.05, sweep_to=170)
    add(s, lowpass(noise(int(0.02 * RATE), rng), 3000), 0, 0.3)
    write("scoop", s, peak=0.7)


def pour(rng, name="pour", secs=0.6, cut=1200, lo=350, hi=950):
    n = int(secs * RATE)
    s = lowpass(noise(n, rng), cut)
    for i in range(n):
        t = i / n
        s[i] *= min(1.0, t * 8) * min(1.0, (1 - t) * 4) * 0.8
    for _ in range(int(secs * 22)):              # bubbles
        f = rng.uniform(lo, hi)
        add(s, tone(f, 0.05, 0.015, sweep_to=f * 1.6), rng.randrange(int(n * 0.85)), 0.35)
    write(name, s, peak=0.6)


def coin(rng):
    s = buf(0.45)
    add(s, tone(1568, 0.4, 0.09, ((1, 1.0), (2.7, 0.2))), 0, 0.7)
    add(s, tone(2093, 0.38, 0.12, ((1, 1.0), (2.7, 0.2))), int(0.07 * RATE), 0.8)
    write("coin", s, peak=0.6)


def click(rng):
    s = tone(1250, 0.035, 0.008, ((1, 1.0), (3, 0.3)))
    write("click", s, peak=0.5)


def serve(rng):
    s = buf(0.35)
    add(s, tone(2400, 0.3, 0.06, ((1, 1.0), (1.54, 0.5), (2.17, 0.3))))
    add(s, tone(220, 0.08, 0.02, sweep_to=140), 0, 0.6)
    write("serve", s, peak=0.6)


def bin_(rng):
    s = tone(110, 0.25, 0.06, ((1, 1.0), (2, 0.3)), sweep_to=55)
    add(s, lowpass(noise(int(0.12 * RATE), rng), 800), 0, 0.8)
    write("bin", s, peak=0.7)


def day(rng):
    s = buf(1.6)
    for k, n in enumerate((72, 76, 79, 84)):
        add(s, tone(midi(n), 1.2, 0.35, ((1, 1.0), (2.76, 0.18), (5.4, 0.05))), int(k * 0.13 * RATE), 0.6)
    write("day", s, peak=0.55)


def main():
    os.makedirs(OUT, exist_ok=True)
    rng = random.Random(7)
    music(rng)
    rain(rng)
    shave(rng)
    scoop(rng)
    pour(rng)
    pour(rng, "ladle", secs=0.55, cut=600, lo=180, hi=480)
    coin(rng)
    click(rng)
    serve(rng)
    bin_(rng)
    day(rng)


main()
