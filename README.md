# SKULLBEAT

Tracker-style drum machine for **Xogot / Godot 4** on iPad.  
K-OS III aesthetic · mono channels · Koala pads · LGPT/LSDJ scene map.

## Architecture

```
UI (main.gd)     multi-window host + pattern banks
SceneMap         top-left 2×3 map (tap / Shift+arrows)
SbClock          tempo / steps
LiveFx           glitch · retrig · stutter · XY · mute
ProjectStore     save / load / export JSON
SynthEngine      voice pool + mix
Instrument       data only
Dsp              pure math
```

## Scene map (top-left)

```
PHR  LCH  SET
TBL  PRJ  EXP
```

| Cell | Window |
|------|--------|
| **PHR** | Phrase tracker |
| **LCH** | Live clip launcher + FX + XY pads |
| **SET** | Project settings (name, BPM) |
| **TBL** | Table view |
| **PRJ** | Save / load projects |
| **EXP** | Export song + import sample |

- **Keyboard:** hold **Shift + arrows** to move map (LGPT/LSDJ style)
- **Touch:** tap a map cell

## Live launcher (LCH)

- **A B C D** — clip banks (4 phrase banks)
- **CH1–4** — channel mute
- **GLITCH / RTRG / STUT / KILL** — performance FX
- **XY A** — X=filter bias · Y=drive/dist
- **XY B** — X=delay wet · Y=delay time

Keys: **G** glitch · **T** retrig · **Y** stutter · **K** kill

## Project

- **SAVE** → `user://projects/<NAME>.skull.json`
- **EXPORT** → tracker text dump + JSON twin
- **Ctrl/Cmd+S** save

## Tracker

4 channels · `NT OC IN FX1 FX2` · mono choke  
FX: **V**el **D**ecay **F**ilter **M**od **P**itch **S**tart-pitch

## Keys

```
1 2 3 4 / Q W E R / A S D F / Z X C V   pads
SPACE play · 0 REC · I import · U AudioShare
Shift+arrows  scene map
```

Pull `main` in Xogot → open project → run.
