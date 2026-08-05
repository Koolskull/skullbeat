# iOS Audio: Sample Import + AUv3 (intention)

Skullbeat targets **Xogot on iPad**. This doc locks the sampling + plugin strategy so we don't lose the plot.

---

## 1. Sample import (SHIP NOW)

### Preferred pipeline: AudioShare

[AudioShare](https://apps.apple.com/app/audioshare/id543859300) is the de-facto audio clipboard / file bridge on iOS.

**User flows we support:**

| Flow | How |
|------|-----|
| **A. Files picker** | In Skullbeat: **IMP** → native file dialog → pick WAV from AudioShare's File Provider / Files / iCloud |
| **B. Share sheet / Open In** | From AudioShare (or any app): Share → Open in Skullbeat (requires export UTI + CFBundleDocumentTypes in export) |
| **C. Jump to AudioShare** | **AS** button / key opens `audioshare://` so user can grab material, then return via A or B |
| **D. Procedural bake** | Built-in one-shots still available for boot/demo instruments |

**Format priority:**
1. **PCM WAV** (8/16/24/32-bit) — fully decoded in `SampleImport.parse_wav`
2. AIFF/CAF — future; for now export WAV from AudioShare
3. MP3/OGG — not offline-decoded yet; message user to convert in AudioShare

**Where samples land:**
- Loaded into the **sample layer** of the target instrument (`Instrument.load_sample_mono`)
- Synth layer stays available (super-instrument = both)
- Root note defaults MIDI 60; user can retune later in INST scene

### AudioShare SDK (optional later)

Full `initiateSoundImport` / pasteboard API needs a **native iOS GDExtension / plugin** bound to AudioShare's public headers. Not required for v1 if Files + WAV works.

When we add a plugin:
- `import_from_audioshare_sdk()` → returns file URL or PCM buffer
- Wire same path into `load_wav_into_instrument` / direct PCM inject

### Implementation map

| File | Role |
|------|------|
| `scripts/sample_import.gd` | Dialog, WAV parse, AudioShare URL open |
| `scripts/instrument.gd` | Sample layer storage |
| `scripts/synth_engine.gd` | Playback of sample layer |
| `scripts/main.gd` | **IMP** / **AS** UI + target INST |

---

## 2. External AUv3 hosting (SHELVED — intention only)

**Goal (future):** load third-party **AUv3** instruments and effects on iPad (e.g. Drambo modules, synths, EQs) as part of the super-instrument or master chain.

### Why it's shelved

| Blocker | Detail |
|---------|--------|
| **Native host** | AUv3 requires `AVAudioEngine` / `AUAudioUnit` host APIs — pure GDScript cannot load plugins |
| **Xogot / Godot export** | Needs a custom **iOS GDExtension** or engine fork that embeds an AUv3 host graph |
| **Sandbox / IAA** | App Group entitlements, Audio Unit capability, background audio mode |
| **UI** | AUv3 generic UI or custom view controllers must be presented natively |
| **Latency / graph** | Mixing our procedural `AudioStreamGenerator` voice engine with AU graph is non-trivial |

### Intended architecture (when un-shelved)

```
[Tracker note-on]
      │
      ├─► Internal SynthEngine voice (current)
      │
      └─► AUv3 Instrument node (MIDI note → AU)
               │
               ▼
         per-inst AU FX inserts (optional)
               │
               ▼
         Master AU bus / Skullbeat EQ+limiter
```

**Phases:**
1. **Research** — confirm Xogot plugin surface (GDExtension? ObjC bridge?)
2. **Minimal host** — load one AUv3 effect on master bus only
3. **Instrument AUv3** — map tracker INST column to AU program/MIDI channel
4. **Presets** — save AU state blobs in project file

### Placeholder API (do not implement yet)

```gdscript
# scripts/auv3_host.gd  — FUTURE / STUB ONLY
class_name AUv3Host
extends Node

## Intention: native plugin implements these methods.
func list_available_units() -> Array:  # [{name, type, subtype, manufacturer}]
	return []

func load_effect(unit_id: String, bus: String = "Master") -> bool:
	push_warning("AUv3 host not linked — shelved")
	return false

func load_instrument(unit_id: String, inst_slot: int) -> bool:
	push_warning("AUv3 host not linked — shelved")
	return false

func note_on_au(inst_slot: int, note: int, velocity: float) -> void:
	pass

func show_au_ui(inst_slot: int) -> void:
	pass
```

UI note on INST / MIX scenes: show **AUv3: SHELVED** label so users know it's planned, not broken.

---

## 3. Entitlements / export checklist (when shipping TestFlight)

- [ ] Background Modes → Audio
- [ ] Document types: `public.audio`, `com.microsoft.waveform-audio`
- [ ] Imported UTIs for WAV/AIFF
- [ ] (Later) App Groups if sharing containers with AudioShare deep integration
- [ ] (Later) Inter-App Audio / Audio Unit Host capability for AUv3

---

## 4. Decision log

| Date | Decision |
|------|----------|
| 2026-08-05 | Ship WAV import via Files/AudioShare provider; jump URL to AudioShare |
| 2026-08-05 | AUv3 host explicitly **shelved** with this doc + stub class; revisit after Xogot native plugin path is clear |
