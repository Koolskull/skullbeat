# Stability notes (Xogot / iPad)

## Tracker UI
- Phrase rows are built on first `_recalc_layout` when `step_labels` is empty.
- Row rebuild is **blocked while `clock.playing`** to avoid audio hitches.
- Alternating row tint uses `modulate` (not ColorRect) so Labels always layout correctly.

## Audio (GDScript AudioStreamGenerator)
Official docs: prefer **22 050 Hz** (or 11 025) from GDScript; default buffer is 0.5 s.

| Setting | Value | Why |
|---------|-------|-----|
| `Dsp.SR` / `mix_rate` | **22050** | Half the CPU vs 44.1k; fine for drums/bass |
| `buffer_length` | **0.35 s** | Headroom against main-thread stalls |
| `MAX_FRAMES` | 2048 | Cap per fill |
| Fill loop | up to 4 chunks/frame | Keep buffer from draining |
| Levels | cached per block | No method calls per sample |

If playback dies after a hard underrun, `_process` restarts `player.play()`.

## XY pads
Use `area.get_meta("wrap")` when parenting — never `get_parent()` of the ColorRect.
