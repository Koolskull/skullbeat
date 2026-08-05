# ☦ SKULLBEAT

**K-OS III aligned 4-channel tracker for Xogot / iPad**

```
╔══════════════════════════════════════════════════════════════╗
║  SKULLBEAT · 4CH TRACKER + SUPER-INSTRUMENTS               ║
║  note | oct | inst | fx1 | fx2   ·  tables per channel     ║
║  synth + sample · FX rack · master EQ/limiter              ║
║  AudioShare WAV import · AUv3 shelved (documented)         ║
╚══════════════════════════════════════════════════════════════╝
```

Inspired by ProTracker / Polyend / Vividtracker + LGPT / LSDJ tables.

## Pull into Xogot

1. Clone `https://github.com/Koolskull/skullbeat`
2. Open in Xogot
3. Run main scene

## Audio engine (now)

- **Super-instrument** per INST number: synth algo + optional sample layer
- Percussion + harmonic textures (kick/snare/hat/clap/bass/texture/FM/noise)
- Tracker FX drive voice params: `V` volume · `D` decay · `F` filter · `M` mod · `P` pitch · `S` start-pitch
- Master chain: soft distortion / chorus / delay / plate-ish reverb + EQ + limiter
- Per-instrument EQ + compressor parameters (engine-side)

## Sample import (AudioShare-friendly)

| Control | Action |
|---------|--------|
| **IMP** button or **I** | Native file picker → load **WAV** into target instrument sample layer |
| **AS** button or **U** | Jump to AudioShare (`audioshare://`) |

**Workflow on iPad:** grab audio in AudioShare → export/share as WAV → Files / Open In / IMP into Skullbeat.  
Target INST = instrument on the selected tracker step (else CH-based default). Successful import auto-auditions the sample.

Details: [`docs/IOS_AUDIO.md`](docs/IOS_AUDIO.md)

## AUv3 external plugins — **SHELVED**

Hosting third-party AUv3 instruments/FX would be excellent on iPad, but needs a **native iOS host** (AVAudioEngine / AUAudioUnit) via GDExtension or Xogot bridge — not possible in pure GDScript.

- Stub: `scripts/auv3_host.gd`
- Full intention, phases, entitlements: [`docs/IOS_AUDIO.md`](docs/IOS_AUDIO.md)
- UI shows `AUv3 SHELVED` so it is intentional, not missing

## Tracker UI

- 4 channels · NOTE · OCT · INST · FX1 · FX2
- Channel header toggles PHRASE ↔ TABLE
- REC + drag-to-edit · Koala-style pad keys (1–4 / QWER / ASDF / ZXCV)
- SPACE play · 0 REC · arrows nav · console / K-OS III aesthetic

## Next

- [ ] LSDJ-style scene map (Shift+arrows / touch) — PHRASE · INST · TABLE · MIX · PADS
- [ ] Full INST editor (sample start/end, loop, root, FX slot UI)
- [ ] Table execution (HOP, VOLM, etc.)
- [ ] Song / chain view
- [ ] Open-in document types for Share sheet
- [ ] AUv3 host when Xogot native plugin path exists

## Aesthetic

K-OS III: pure black, sharp 1px borders, yellow accents, console labels, ☦ headers, no rounded corners.
