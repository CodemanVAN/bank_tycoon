#!/usr/bin/env python3
"""
Self-owned procedural audio asset generator for Starway Bank / Bank Tycoon.
Generates 12 clean, click-free 16-bit 44100 Hz mono PCM .wav files under
bank_tycoon_demo/assets/audio/ using only Python standard library modules:
  - bgm_starway_lobby.wav (32.000s seamless loop + embedded RIFF smpl chunk)
  - 11 gameplay & UI SFX

Includes built-in WAV header, frame count, peak (< 0.90), boundary silence,
and loop continuity verification.
"""

from __future__ import annotations

import math
import struct
import wave
from pathlib import Path

AUDIO_DIR = Path(__file__).resolve().parent.parent / "assets" / "audio"

SAMPLE_RATE = 44100
CHANNELS = 1
SAMPWIDTH = 2
MAX_INT16 = 32767
MAX_PEAK_RATIO = 0.89

TWO_PI = 2.0 * math.pi

NOTE_FREQS: dict[str, float] = {
    "C3": 130.8128,
    "Eb3": 155.5635,
    "D3": 146.8324,
    "E3": 164.8138,
    "F3": 174.6141,
    "G3": 195.9977,
    "A3": 220.0000,
    "B3": 246.9417,
    "C4": 261.6256,
    "D4": 293.6648,
    "E4": 329.6276,
    "F4": 349.2282,
    "G4": 391.9954,
    "A4": 440.0000,
    "B4": 493.8833,
    "C5": 523.2511,
    "D5": 587.3295,
    "Eb5": 622.2540,
    "E5": 659.2551,
    "F#5": 739.9888,
    "G5": 783.9909,
    "A5": 880.0000,
    "B5": 987.7666,
    "C6": 1046.5023,
    "C#6": 1108.7305,
    "E6": 1318.5102,
    "B6": 1975.5332,
    "E7": 2637.0205,
}


def adsr_cos(t: float, dur: float, attack: float, release: float) -> float:
    if t < 0.0 or t > dur or dur <= 0.0:
        return 0.0
    env = 1.0
    if attack > 0.0 and t < attack:
        env *= 0.5 * (1.0 - math.cos(math.pi * t / attack))
    if release > 0.0 and t > dur - release:
        rem = max(0.0, dur - t)
        env *= 0.5 * (1.0 - math.cos(math.pi * rem / release))
    return env


def rhodes_voice(t: float, freq: float, dur: float) -> float:
    if t < 0.0 or t > dur:
        return 0.0
    env = adsr_cos(t, dur, 0.008, min(0.045, dur * 0.4)) * math.exp(-1.6 * t)
    f1 = math.sin(TWO_PI * freq * t)
    f2 = 0.22 * math.sin(TWO_PI * 2.0 * freq * t) * math.exp(-4.0 * t)
    tine = 0.14 * math.sin(TWO_PI * 7.0 * freq * t) * math.exp(-35.0 * t)
    return (f1 + f2 + tine) * env


def normalize_and_quantize(samples: list[float], target_peak: float) -> list[int]:
    if not samples:
        return []
    peak = max(abs(x) for x in samples)
    scale = (target_peak / peak) if peak > 1e-12 else 0.0
    out: list[int] = []
    for x in samples:
        v = max(-MAX_PEAK_RATIO, min(MAX_PEAK_RATIO, x * scale))
        out.append(int(round(v * MAX_INT16)))
    return out


def write_wav(path: Path, int_samples: list[int], loop_smpl: bool = False) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as wf:
        wf.setnchannels(CHANNELS)
        wf.setsampwidth(SAMPWIDTH)
        wf.setframerate(SAMPLE_RATE)
        raw = struct.pack(f"<{len(int_samples)}h", *int_samples)
        wf.writeframes(raw)

    if loop_smpl:
        data = bytearray(path.read_bytes())
        sample_period_ns = int(round(1_000_000_000 / SAMPLE_RATE))
        nframes = len(int_samples)
        # 8-byte chunk header ('smpl', 60) + 9 uint32 sampler fields + 6 uint32 loop fields
        smpl = b"smpl" + struct.pack(
            "<10I6I",
            60, 0, 0, sample_period_ns, 60, 0, 0, 0, 1, 0,
            0, 0, 0, nframes - 1, 0, 0,
        )
        data.extend(smpl)
        struct.pack_into("<I", data, 4, len(data) - 8)
        path.write_bytes(bytes(data))


def synth_bgm_starway_lobby() -> tuple[list[int], int]:
    """32.000s (1,411,200 frames) warm Lo-Fi/Rhodes fintech lobby seamless loop."""
    duration = 32.0
    total_frames = int(round(duration * SAMPLE_RATE))  # 1,411,200
    bar_samples = 117600  # 90 BPM, 4/4 -> 29,400 samples/beat -> 117,600 samples/bar (12 bars = 1,411,200)
    beat_samples = 29400

    buf = [0.0] * total_frames

    def q_freq(f: float) -> float:
        return round(f * duration) / duration

    # Layer 1: Exact T-periodic warm ambient pad & sub-root (C4 + G4 + E4 bed)
    pad_freqs = [q_freq(NOTE_FREQS["C3"]), q_freq(NOTE_FREQS["G3"]), q_freq(NOTE_FREQS["E4"])]
    pad_weights = [0.22, 0.14, 0.10]
    lfo_hz = 4.0 / duration
    for i in range(total_frames):
        t = i / SAMPLE_RATE
        lfo = 0.85 + 0.15 * math.sin(TWO_PI * lfo_hz * t)
        val = 0.0
        for pf, pw in zip(pad_freqs, pad_weights):
            val += pw * math.sin(TWO_PI * pf * t)
        buf[i] += val * lfo

    # Layer 2: 12-bar warm Rhodes chord progression (Fmaj9 -> G6/9 -> Em7 -> Am9 x2 -> Dm9 -> G13 -> Cmaj9 -> Am9)
    chords: list[list[str]] = [
        ["F3", "A3", "C4", "E4", "G4"],   # Bar 1: Fmaj9
        ["G3", "B3", "D4", "E4", "A4"],   # Bar 2: G6/9
        ["E3", "G3", "B3", "D4", "G4"],   # Bar 3: Em7
        ["A3", "C4", "E4", "G4", "B4"],   # Bar 4: Am9
        ["F3", "A3", "C4", "E4", "G4"],   # Bar 5: Fmaj9
        ["G3", "B3", "D4", "E4", "A4"],   # Bar 6: G6/9
        ["E3", "G3", "B3", "D4", "G4"],   # Bar 7: Em7
        ["A3", "C4", "E4", "G4", "B4"],   # Bar 8: Am9
        ["D3", "F3", "A3", "C4", "E4"],   # Bar 9: Dm9
        ["G3", "B3", "D4", "F4", "E5"],   # Bar 10: G13
        ["C3", "E3", "G3", "B3", "D4"],   # Bar 11: Cmaj9
        ["A3", "C4", "E4", "G4", "B4"],   # Bar 12: Am9
    ]

    def add_note_wrap(start_sample: int, freq: float, note_dur: float, amp: float) -> None:
        n_len = int(round(note_dur * SAMPLE_RATE))
        for k in range(n_len):
            t = k / SAMPLE_RATE
            idx = (start_sample + k) % total_frames
            buf[idx] += amp * rhodes_voice(t, freq, note_dur)

    for bar_idx, chord in enumerate(chords):
        bar_start = bar_idx * bar_samples
        # Gentle Rhodes comping on beat 1 and softer echo on beat 3.5 in bars 5..8
        for voice_idx, note_name in enumerate(chord):
            freq = NOTE_FREQS[note_name]
            strum_offset = voice_idx * int(0.018 * SAMPLE_RATE)
            add_note_wrap(bar_start + strum_offset, freq, 2.35, 0.11 if voice_idx > 0 else 0.14)
        if 4 <= bar_idx <= 7:
            sync_start = bar_start + int(2.5 * beat_samples)
            for voice_idx, note_name in enumerate(chord[1:]):
                add_note_wrap(sync_start + voice_idx * 400, NOTE_FREQS[note_name], 1.10, 0.06)

    # Layer 3: Sparse pentatonic Rhodes bell melody (C5, D5, E5, G5, A5, B5)
    melody_events: list[tuple[float, str, float, float]] = [
        (0.5, "E5", 1.1, 0.24),
        (2.0, "G5", 1.2, 0.26),
        (5.5, "A5", 1.3, 0.28),
        (7.5, "E5", 1.0, 0.22),
        (9.0, "D5", 1.4, 0.25),
        (12.5, "C5", 1.3, 0.24),
        (14.5, "E5", 1.1, 0.26),
        (17.0, "G5", 1.4, 0.28),
        (19.5, "B5", 1.2, 0.24),
        (21.5, "A5", 1.3, 0.26),
        (24.5, "G5", 1.1, 0.24),
        (26.5, "E5", 1.2, 0.25),
        (29.0, "D5", 1.4, 0.24),
        (33.5, "E5", 1.2, 0.26),
        (36.5, "A5", 1.3, 0.28),
        (38.5, "G5", 1.4, 0.25),
        (41.5, "D5", 1.3, 0.24),
        (44.5, "E5", 1.2, 0.25),
        (46.5, "C5", 1.1, 0.22),
    ]
    for beat_pos, note_name, dur, amp in melody_events:
        start_s = int(round(beat_pos * beat_samples))
        add_note_wrap(start_s, NOTE_FREQS[note_name], dur, amp)

    return normalize_and_quantize(buf, 0.55), total_frames


def _render_buffer(dur: float) -> tuple[list[float], int]:
    nframes = int(round(dur * SAMPLE_RATE))
    return [0.0] * nframes, nframes


def synth_sfx_ui_click() -> tuple[list[int], int]:
    dur = 0.065
    buf, n = _render_buffer(dur)
    phase = 0.0
    for i in range(n):
        t = i / SAMPLE_RATE
        f = 1200.0 - (520.0 * (t / dur))
        phase += TWO_PI * f / SAMPLE_RATE
        env = adsr_cos(t, dur, 0.002, 0.015) * math.exp(-t / 0.012)
        buf[i] = (math.sin(phase) + 0.25 * math.sin(2.0 * phase)) * env
    return normalize_and_quantize(buf, 0.68), n


def synth_sfx_ui_select() -> tuple[list[int], int]:
    dur = 0.130
    buf, n = _render_buffer(dur)
    for i in range(n):
        t = i / SAMPLE_RATE
        val = 0.0
        if t <= 0.080:
            e1 = adsr_cos(t, 0.080, 0.004, 0.030)
            f1 = NOTE_FREQS["C5"]
            val += (math.sin(TWO_PI * f1 * t) + 0.20 * math.sin(TWO_PI * 2.0 * f1 * t)) * e1
        if t >= 0.045:
            t2 = t - 0.045
            e2 = adsr_cos(t2, dur - 0.045, 0.004, 0.050)
            f2 = NOTE_FREQS["G5"]
            val += (math.sin(TWO_PI * f2 * t2) + 0.20 * math.sin(TWO_PI * 2.0 * f2 * t2)) * e2
        buf[i] = val
    return normalize_and_quantize(buf, 0.70), n


def synth_sfx_ui_error() -> tuple[list[int], int]:
    dur = 0.240
    buf, n = _render_buffer(dur)
    for i in range(n):
        t = i / SAMPLE_RATE
        val = 0.0
        if t <= 0.110:
            f1 = NOTE_FREQS["Eb3"]
            e1 = adsr_cos(t, 0.110, 0.005, 0.035)
            val += (
                math.sin(TWO_PI * f1 * t)
                + 0.25 * math.sin(TWO_PI * 3.0 * f1 * t)
                + 0.10 * math.sin(TWO_PI * 5.0 * f1 * t)
            ) * e1
        if t >= 0.095:
            t2 = t - 0.095
            f2 = NOTE_FREQS["C3"]
            e2 = adsr_cos(t2, dur - 0.095, 0.005, 0.060)
            val += (
                math.sin(TWO_PI * f2 * t2)
                + 0.25 * math.sin(TWO_PI * 3.0 * f2 * t2)
                + 0.10 * math.sin(TWO_PI * 5.0 * f2 * t2)
            ) * e2
        buf[i] = val
    return normalize_and_quantize(buf, 0.75), n


def synth_sfx_cash_chime() -> tuple[list[int], int]:
    dur = 0.340
    buf, n = _render_buffer(dur)
    tones = [(0.000, NOTE_FREQS["E6"], 1.0), (0.055, NOTE_FREQS["B6"], 0.9), (0.085, NOTE_FREQS["E7"], 0.25)]
    for i in range(n):
        t = i / SAMPLE_RATE
        tail_fade = adsr_cos(t, dur, 0.002, 0.025)
        val = 0.0
        for onset, freq, weight in tones:
            if t >= onset:
                tl = t - onset
                env = adsr_cos(tl, dur - onset, 0.002, 0.025) * math.exp(-tl / 0.085)
                val += weight * math.sin(TWO_PI * freq * tl) * env
        buf[i] = val * tail_fade
    return normalize_and_quantize(buf, 0.78), n


def synth_sfx_loan_approve() -> tuple[list[int], int]:
    dur = 0.420
    buf, n = _render_buffer(dur)
    stamp_phase = 0.0
    notes = [(0.050, NOTE_FREQS["C5"]), (0.120, NOTE_FREQS["E5"]), (0.190, NOTE_FREQS["G5"])]
    for i in range(n):
        t = i / SAMPLE_RATE
        val = 0.0
        if t < 0.065:
            f_thud = 140.0 - 85.0 * (t / 0.065)
            stamp_phase += TWO_PI * f_thud / SAMPLE_RATE
            val += 0.65 * math.sin(stamp_phase) * adsr_cos(t, 0.065, 0.003, 0.025)
        for onset, freq in notes:
            if t >= onset:
                tl = t - onset
                rem = dur - onset
                env = adsr_cos(tl, rem, 0.003, 0.040) * math.exp(-3.2 * tl)
                val += (math.sin(TWO_PI * freq * tl) + 0.18 * math.sin(TWO_PI * 2.0 * freq * tl)) * env
        buf[i] = val
    return normalize_and_quantize(buf, 0.80), n


def synth_sfx_loan_reject() -> tuple[list[int], int]:
    dur = 0.300
    buf, n = _render_buffer(dur)
    for i in range(n):
        t = i / SAMPLE_RATE
        val = 0.0
        if t <= 0.150:
            f1 = NOTE_FREQS["F4"]
            e1 = adsr_cos(t, 0.150, 0.005, 0.045)
            val += (math.sin(TWO_PI * f1 * t) + 0.18 * math.sin(TWO_PI * 3.0 * f1 * t)) * e1
        if t >= 0.120:
            t2 = t - 0.120
            f2 = NOTE_FREQS["C4"]
            e2 = adsr_cos(t2, dur - 0.120, 0.005, 0.070)
            val += (math.sin(TWO_PI * f2 * t2) + 0.18 * math.sin(TWO_PI * 3.0 * f2 * t2)) * e2
        buf[i] = val
    return normalize_and_quantize(buf, 0.72), n


def synth_sfx_customer_bell() -> tuple[list[int], int]:
    dur = 0.480
    buf, n = _render_buffer(dur)
    dings = [(0.000, NOTE_FREQS["A5"]), (0.130, NOTE_FREQS["C#6"])]
    for i in range(n):
        t = i / SAMPLE_RATE
        val = 0.0
        for onset, freq in dings:
            if t >= onset:
                tl = t - onset
                env = adsr_cos(tl, dur - onset, 0.003, 0.040) * math.exp(-tl / 0.110)
                partial = (
                    math.sin(TWO_PI * freq * tl)
                    + 0.30 * math.sin(TWO_PI * 2.0 * freq * tl) * math.exp(-4.0 * tl)
                    + 0.12 * math.sin(TWO_PI * 3.01 * freq * tl) * math.exp(-8.0 * tl)
                )
                val += partial * env
        buf[i] = val
    return normalize_and_quantize(buf, 0.74), n


def synth_sfx_event_alert() -> tuple[list[int], int]:
    dur = 0.460
    buf, n = _render_buffer(dur)
    seq = [
        (0.000, NOTE_FREQS["D5"], 0.130),
        (0.090, NOTE_FREQS["A5"], 0.130),
        (0.180, NOTE_FREQS["F#5"], 0.130),
        (0.270, NOTE_FREQS["A5"], 0.190),
    ]
    for i in range(n):
        t = i / SAMPLE_RATE
        val = 0.0
        for onset, freq, ndur in seq:
            if onset <= t <= onset + ndur:
                tl = t - onset
                env = adsr_cos(tl, ndur, 0.004, min(0.060, ndur * 0.45)) * math.exp(-4.5 * tl)
                val += (math.sin(TWO_PI * freq * tl) + 0.15 * math.sin(TWO_PI * 4.0 * freq * tl) * math.exp(-25.0 * tl)) * env
        buf[i] = val
    return normalize_and_quantize(buf, 0.78), n


def synth_sfx_risk_warning() -> tuple[list[int], int]:
    dur = 0.560
    buf, n = _render_buffer(dur)
    pulses = [(0.000, 0.220), (0.240, 0.320)]
    f_a = NOTE_FREQS["A4"]
    f_eb = NOTE_FREQS["Eb5"]
    for i in range(n):
        t = i / SAMPLE_RATE
        val = 0.0
        for onset, pdur in pulses:
            if onset <= t <= onset + pdur:
                tl = t - onset
                env = adsr_cos(tl, pdur, 0.006, 0.090)
                val += (0.65 * math.sin(TWO_PI * f_a * tl) + 0.45 * math.sin(TWO_PI * f_eb * tl)) * env
        buf[i] = val
    return normalize_and_quantize(buf, 0.78), n


def synth_sfx_day_complete() -> tuple[list[int], int]:
    dur = 0.750
    buf, n = _render_buffer(dur)
    arp = ["C4", "G4", "B4", "D5", "E5"]
    for i in range(n):
        t = i / SAMPLE_RATE
        val = 0.0
        for idx, nname in enumerate(arp):
            onset = idx * 0.065
            if t >= onset:
                tl = t - onset
                rem = dur - onset
                env = adsr_cos(tl, rem, 0.008, 0.080) * math.exp(-tl / 0.350)
                f = NOTE_FREQS[nname]
                val += (math.sin(TWO_PI * f * tl) + 0.22 * math.sin(TWO_PI * 2.0 * f * tl) * math.exp(-4.0 * tl)) * env
        buf[i] = val
    return normalize_and_quantize(buf, 0.76), n


def synth_sfx_upgrade_success() -> tuple[list[int], int]:
    dur = 0.620
    buf, n = _render_buffer(dur)
    steps = [
        (0.000, NOTE_FREQS["C5"], 0.120),
        (0.070, NOTE_FREQS["E5"], 0.120),
        (0.140, NOTE_FREQS["G5"], 0.480),
        (0.210, NOTE_FREQS["C6"], 0.410),
    ]
    for i in range(n):
        t = i / SAMPLE_RATE
        val = 0.0
        for onset, freq, ndur in steps:
            if onset <= t <= onset + ndur:
                tl = t - onset
                rel = 0.150 if ndur > 0.300 else 0.035
                env = adsr_cos(tl, ndur, 0.004, rel) * math.exp(-2.2 * tl)
                val += (math.sin(TWO_PI * freq * tl) + 0.20 * math.sin(TWO_PI * 2.0 * freq * tl)) * env
        buf[i] = val
    return normalize_and_quantize(buf, 0.80), n


def verify_outputs(expected: dict[str, tuple[int, bool]]) -> None:
    assert len(expected) == 12, f"Expected 12 WAV specs, got {len(expected)}"
    for filename, (expected_frames, expect_smpl) in sorted(expected.items()):
        path = AUDIO_DIR / filename
        assert path.exists(), f"Missing WAV file: {path}"
        with wave.open(str(path), "rb") as wf:
            assert wf.getnchannels() == CHANNELS, f"{filename}: channels != 1"
            assert wf.getsampwidth() == SAMPWIDTH, f"{filename}: sampwidth != 2"
            assert wf.getframerate() == SAMPLE_RATE, f"{filename}: framerate != 44100"
            assert wf.getcomptype() == "NONE", f"{filename}: comptype != NONE"
            nframes = wf.getnframes()
            assert nframes == expected_frames, f"{filename}: frames {nframes} != {expected_frames}"
            raw = wf.readframes(nframes)

        samples = struct.unpack(f"<{nframes}h", raw)
        peak_ratio = max(abs(s) for s in samples) / float(MAX_INT16)
        rms = math.sqrt(sum((s / float(MAX_INT16)) ** 2 for s in samples) / nframes)
        assert peak_ratio < 0.90, f"{filename}: peak_ratio {peak_ratio:.4f} >= 0.90"
        assert rms > 0.01, f"{filename}: rms {rms:.4f} <= 0.01 (too quiet/silent)"

        if expect_smpl:
            loop_diff = abs(samples[0] - samples[-1]) / float(MAX_INT16)
            assert loop_diff < 0.01, f"{filename}: loop boundary step {loop_diff:.5f} >= 0.01"
            raw_bytes = path.read_bytes()
            smpl_pos = raw_bytes.rfind(b"smpl")
            assert smpl_pos > 44, f"{filename}: missing RIFF smpl chunk"
            chunk_size = struct.unpack_from("<I", raw_bytes, smpl_pos + 4)[0]
            assert chunk_size == 60, f"{filename}: unexpected smpl chunk size {chunk_size}"
            loop_start, loop_end = struct.unpack_from("<2I", raw_bytes, smpl_pos + 44 + 8)
            assert loop_start == 0 and loop_end == nframes - 1, (
                f"{filename}: smpl loop bounds ({loop_start}, {loop_end}) != (0, {nframes - 1})"
            )
        else:
            start_ratio = abs(samples[0]) / float(MAX_INT16)
            end_ratio = abs(samples[-1]) / float(MAX_INT16)
            assert start_ratio < 0.005, f"{filename}: start sample {start_ratio:.5f} >= 0.005"
            assert end_ratio < 0.005, f"{filename}: end sample {end_ratio:.5f} >= 0.005"


def main() -> None:
    generators: dict[str, tuple[callable, bool]] = {
        "bgm_starway_lobby.wav": (synth_bgm_starway_lobby, True),
        "sfx_ui_click.wav": (synth_sfx_ui_click, False),
        "sfx_ui_select.wav": (synth_sfx_ui_select, False),
        "sfx_ui_error.wav": (synth_sfx_ui_error, False),
        "sfx_cash_chime.wav": (synth_sfx_cash_chime, False),
        "sfx_loan_approve.wav": (synth_sfx_loan_approve, False),
        "sfx_loan_reject.wav": (synth_sfx_loan_reject, False),
        "sfx_customer_bell.wav": (synth_sfx_customer_bell, False),
        "sfx_event_alert.wav": (synth_sfx_event_alert, False),
        "sfx_risk_warning.wav": (synth_sfx_risk_warning, False),
        "sfx_day_complete.wav": (synth_sfx_day_complete, False),
        "sfx_upgrade_success.wav": (synth_sfx_upgrade_success, False),
    }

    expected: dict[str, tuple[int, bool]] = {}
    for filename, (fn, is_bgm) in generators.items():
        samples, nframes = fn()
        write_wav(AUDIO_DIR / filename, samples, loop_smpl=is_bgm)
        expected[filename] = (nframes, is_bgm)

    verify_outputs(expected)
    print(f"[generate_audio_assets] OK: {len(expected)} 16-bit 44100 Hz PCM WAVs generated & verified.")


if __name__ == "__main__":
    main()
