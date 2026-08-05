# SKULLBEAT

Tracker-style drum machine for **Xogot / Godot 4** on iPad.  
K-OS III aesthetic · mono channels · Koala-style pads.

## Architecture (minimal layers)

```
UI (main.gd)          pattern edit, playhead paint, input
    │
SbClock               tempo / step events only
    │
SynthEngine           voice pool + mix + generator fill
    │
Instrument            data only (sample | synth | fx slots)
    │
Dsp                   pure math: env, noise, clip, freq, bake
```

Each layer does one job. No DSP in UI. No UI in engine. No state in `Dsp`.

### Cost rules
- **Sample XOR synth** per voice (never both)
- Master path = gain + soft clip (bus FX wet defaults **0**)
- Hard cap **384 frames/tick** so the clock never starves
- Playhead recolors **2 rows**, not the whole grid
- Voices stored as parallel packed arrays (no dict lookup in render)

### Scripts
| File | Role |
|------|------|
| `scripts/dsp.gd` | Pure DSP units |
| `scripts/instrument.gd` | Super-instrument data |
| `scripts/synth_engine.gd` | Mixer / voices / generator |
| `scripts/clock.gd` | Step clock |
| `scripts/main.gd` | Tracker UI |
| `scripts/sample_import.gd` | WAV / AudioShare |
| `scripts/auv3_host.gd` | AUv3 shelved stub |
| `docs/IOS_AUDIO.md` | iOS audio roadmap |

## Tracker
4 channels · `NT OC IN FX1 FX2` · phrase / table toggle per channel  
FX letters: **V**el **D**ecay **F**ilter **M**od **P**itch **S**tart-pitch

## Keys (Koala-style)
```
1 2 3 4     pads 1–4
Q W E R     pads 5–8
A S D F     pads 9–12
Z X C V     pads 13–16
SPACE play/stop · 0 REC · I import · U AudioShare
```

## Open in Xogot
Pull `main` → open project → run `scenes/main.tscn`.
