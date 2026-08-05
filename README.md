# ☦ SKULLBEAT

**K-OS III aligned drum machine + step sequencer + scene launcher**

Built for **Xogot** (Godot on iPad).

Pixel aesthetic. No rounded corners. Sharp borders. Dense tracker-inspired UI matching Datamoshpit / KoolDraw / Skullmash.

```
╔══════════════════════════════════════════════════════════════╗
║  SKULLBEAT · STEP SEQUENCER + SCENE LAUNCHER · K-OS III     ║
║  Touch-first · 8 tracks × 16 steps · Scenes · Live pads     ║
╚══════════════════════════════════════════════════════════════╝
```

## Status

Early scaffold. Core sequencer + UI in progress.

## Features (target)

- 8 drum tracks × 16 steps
- Pattern storage + Scene launcher (Ableton-style clip/scene triggers)
- Live drum pads
- Tempo / swing (later)
- Sample loading (WAV)
- Export patterns for Datamoshpit / PRODEV pipeline
- Visual identity locked to K-OS III rules: no rounded corners, black bg, yellow accents, monospace/pixel labels, ☦ headers

## How to run in Xogot

1. Install [Working Copy](https://workingcopy.app) on iPad (or use any Git client that works with Xogot).
2. Clone `https://github.com/Koolskull/skullbeat.git`
3. Open the project folder in Xogot (via Files / iCloud / Working Copy).
4. Open `project.godot` or the main scene and run.

Alternatively: create a new Godot project in Xogot and copy-paste the files from this repo.

## Aesthetic Rules (from K-OS III)

- No rounded corners
- Sharp 1px borders
- Black / near-black backgrounds (`#000`, `#0a0a0a`, `#1a1a1a`)
- Yellow (`#ffff00`) for primary active/highlight
- Gray text (`#555` inactive, `#aaa`/`#fff` active)
- Dense, small labels, letter-spacing
- Orthodox cross headers where appropriate
- Window/title style matching AppWindow.tsx

## License

Koolskull / K-OS-III ecosystem.
