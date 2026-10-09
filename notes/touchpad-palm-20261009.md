# Touchpad palm rejection: ChromeOS's rules on Omarchy, 2026-10-09

## The pad

Elan i2c `04f3:014e` (`Elan Touchpad`, event1), 119×73 mm, 31 units/mm, 5 slots. Reports per contact
`ABS_MT_PRESSURE` 0–255 and `ABS_MT_TOUCH_MAJOR/MINOR` (contact ellipse, max 1890/1875), plus `ABS_DISTANCE` (hover bit)
and `ABS_TOOL_WIDTH`; no `ABS_MT_TOOL_TYPE` (no firmware palm flag). libinput quirks: `ModelChromebook=1`,
`AttrPressureRange=10:8`, no palm size/pressure thresholds, so libinput only did edge-palm and thumb detection here
(disable-while-typing is off on purpose, see the omarchy-setup browser-game note).

## What ChromeOS does

Chrome's touchpad stack is the ChromiumOS gestures library, not libinput. Its `PalmClassifyingFilterInterpreter`
(src/palm_classifying_filter_interpreter.cc) defaults: Palm Pressure 200, Palm Width 21.2 mm, Multiple Palm Width 75 mm,
Fat Finger ratios 1.4/1.3 + 15 mm, Tap Exclusion Border 8 mm, Palm Edge Zone 14 mm, Palm Eval Timeout 0.1 s, Palm
Stationary 2 s / 4 mm, Pointing 8 mm (≤0.3 mm reverse), split 4 mm. `ImmediateInterpreter`'s "Keyboard Palm Prevent
Timeout" 0.5 s blocks taps (not motion) after a keystroke. ChromeOS's `/etc/gesture/40-touchpad-cmt.conf` on this
machine has no board-specific palm values; the Elan section only sets pressure calibration (slope 3.1416, offset 0,
Tap Minimum Pressure 10), so stock defaults apply: palm at raw pressure ≥ 64/255 or single-contact width ≥ 21.2 mm
(raw touch major ≥ 657).

## quigon-palm-filter

[`quigon-palm-filter`](../port/quigon/root/usr/local/libexec/quigon/quigon-palm-filter) ports that classifier and the
0.5 s post-keystroke tap guard (a contact landing within 0.5 s of a non-modifier keypress is held back until it lives
0.2 s or moves 2 mm). Plumbing from the Zenbook A16 filter in omarchy-setup: grab the pad, re-emit accepted contacts
(position, pressure, touch major) on a uinput "Elan Touchpad (palm filter)", release on exit. Hidden contacts are logged
(reason, duration, max pressure/width, start position) to the journal; key codes never are. All thresholds are
overridable via environment variables. `systemctl stop quigon-palm-filter` returns the raw pad.

Not used from the Zenbook filter: its typing-session heuristics, which exist because that pad reports neither pressure
nor size; this pad gives ChromeOS's own inputs.
