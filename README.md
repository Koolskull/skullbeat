# SKULLBEAT

Tracker-style drum machine for **Xogot / Godot 4** on iPad.  
K-OS III aesthetic · mono channels · Koala pads · LGPT/LSDJ scene map.

## Scene map (top-left)

```
PHR  LCH  INS  MIX
TBL  PRJ  SET  EXP
```

| Cell | Window |
|------|--------|
| **PHR** | Phrase tracker |
| **LCH** | Live clip launcher + FX + XY |
| **INS** | Instrument editor |
| **MIX** | Channel + master levels |
| **TBL** | Table view |
| **PRJ** | Save / load |
| **SET** | Project settings |
| **EXP** | Export song + import sample |

**Shift + arrows** move map · **tap** cells on touch.

## Instrument editor (INS)

- Browse inst `00–3F` with `<` `>` or **[ ]**
- **SYNTH / SAMP** source select (sample XOR synth)
- **ALGO±** cycle kick/snare/hat/clap/bass/texture/fm/noise
- **GAIN±** instrument level
- **FX1–3** type cycle + wet (rack data; bus wet still live via LCH)
- **PREV / P** audition · **IMP** load WAV into this inst

## Mixer (MIX)

- Faders **CH1–4** + **MST** (0–150%)
- Tap/drag fader · **M** mute per channel
- Levels applied in the engine voice mix (cheap)

## Live launcher (LCH)

A–D banks · mute · GLITCH/RTRG/STUT/KILL · XY pads  
Keys: **G T Y K**

## Project

SAVE → `user://projects/` · EXPORT text+JSON · **Ctrl/Cmd+S**

## Architecture

```
UI → SceneMap / Clock / LiveFx / ProjectStore
   → SynthEngine → Instrument → Dsp
```

Pull `main` in Xogot and run.
