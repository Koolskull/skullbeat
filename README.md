# ☦ SKULLBEAT

**K-OS III aligned 4-channel tracker + tables for Xogot / iPad**

```
╔══════════════════════════════════════════════════════════════╗
║  SKULLBEAT · 4CH TRACKER + TABLES · K-OS III               ║
║  note | oct | inst | fx1 | fx2   ·  per-channel Tables     ║
║  console font · dynamic layout · REC + drag-to-edit         ║
╚══════════════════════════════════════════════════════════════╝
```

Inspired by ProTracker / Polyend Tracker / Vividtracker layout + LittleGPTracker / LSDJ style Tables (subroutine automation).

## Current State

- **4 channels** side-by-side
- Each step: **NOTE · OCTAVE · INSTRUMENT · FX1 · FX2**
- Tap channel header to switch that channel between **PHRASE** view and **TABLE** view
- Tables are the subroutine/automation layer (HOP-style loops, commands — scaffold ready)
- **REC** toggle: when on, tap a cell then drag up/down to edit values (note cycle, octave, instrument number)
- Console-style fixed-width feel, dense, no rounded corners, yellow active / red playhead / REC indicator
- Layout recalculates visible rows to fill available screen height on iPad

## How to pull into Xogot

1. Clone or pull `https://github.com/Koolskull/skullbeat`
2. Open in Xogot
3. Run main scene

## Next priorities

- Actual audio engine (samples or simple synth voices per instrument)
- Proper hex / command entry for FX columns and full Table editing
- Phrase length / pattern chaining / Song view
- Table execution engine (VOLM, HOP, transpose, etc. like LGPT)
- Sample browser that matches the aesthetic

## Aesthetic

Locked to K-OS III: pure black, sharp 1px borders, yellow accents, console labels, ☦ headers, no rounded anything.
