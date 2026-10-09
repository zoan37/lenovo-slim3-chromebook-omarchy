# Keyboard top row and audio, 2026-10-09

## Top row (cros_ec keyboard, `event2`)

`libinput debug-events --show-keycodes` while pressing the top row left to right:

| Key | evdev | Handling |
|---|---|---|
| Esc | `KEY_ESC` 1 | — |
| Back / Refresh | `KEY_BACK` 158 / `KEY_REFRESH` 173 | Chrome handles them natively |
| Fullscreen | `KEY_FULL_SCREEN` 372 | `code:380` → `hl.dsp.window.fullscreen` |
| Overview | `KEY_SCALE` 120 | `code:128` → `omarchy-menu toggle apps` |
| Screenshot | `KEY_SYSRQ` 99 (Print) | Omarchy's stock Print bind |
| Brightness ↓/↑ | `KEY_BRIGHTNESSDOWN/UP` 224/225 | stock (works; `/sys/class/backlight/backlight`) |
| Keyboard backlight | `KEY_KBDILLUMTOGGLE` 228 | stock `XF86KbdLightOnOff` → `omarchy-brightness-keyboard cycle` (`chromeos::kbd_backlight`, 0–100) |
| Mic mute, Mute, Vol ↓/↑ | 248, 113, 114, 115 | stock XF86Audio* binds |
| Accessibility | `KEY_ACCESSIBILITY` 590 | unbound |
| Dictate | `KEY_DICTATE` 586 | `code:594` → `voxtype record toggle` if voxtype is installed (it isn't yet) |
| Lock (top right) | **`KEY_SLEEP` 142** | `code:150` → `omarchy-system-lock`; logind `HandleSuspendKey=ignore` |

Before the fix the lock key suspended the laptop through logind (that is how SSH dropped mid-session); suspend/resume
itself worked (`mem_sleep` is `s2idle` only). Hyprland 0.56's Lua parser accepts `code:NNN` (xkb keycode = evdev + 8);
`hyprctl binds -j` shows those binds with keycode 0, which is cosmetic.

## Audio

- Card `mt8189_1019_rt5682s` (driver id `mt8189_1019_rt5`, card id `mt81891019rt568`): RT1019 speaker amp + RT5682S headset codec,
  DMIC.
- **ALARM's PipeWire was missing `alsa-card-profiles`** (and `pipewire-pulse` was not installed), so WirePlumber created no
  ALSA device at all. Installing `pipewire-pulse pipewire-alsa` pulled in `alsa-card-profiles`.
- ChromeOS has an exact UCM v1 profile, `/usr/share/alsa/ucm/mt8189_1019_rt5682s.quigon` (CRAS also has
  `/etc/cras/quigon.rt1019.rt5682s/` with a MaxxChrome DSP plugin, not used). Converted to UCM2:
  [`port/quigon/root/usr/share/alsa/ucm2/conf.d/mt8189_1019_rt5/`](../port/quigon/root/usr/share/alsa/ucm2/conf.d/mt8189_1019_rt5/).
  Changes from ChromeOS's file: no `cdev`, `hw:${CardId},N` PCMs, standard device names (Speaker, Headphones, Mic, Headset),
  `JackControl` (kcontrols `Headphone Jack`, `Headset Mic Jack`) instead of CRAS's `JackDev`, priorities.
- **PipeWire's ACP probes every PCM before any device EnableSequence runs**, and these MediaTek DPCM front ends reject
  `hw_params` (`Invalid argument`) until routed to a back end, so ACP dropped the whole HiFi profile
  (`Profile HiFi not supported`). Fix: the front-end routes (`I2SOUT1_CH* DL0_CH*` speaker, `I2SOUT0_CH* DL1_CH*` headphone,
  `UL0_CH* AP_DMIC_UL_CH*` DMIC, `UL1_CH* I2SIN0_CH*` headset mic) are set in the verb; the codec mixer switches stay per
  device. `spa-acp-tool -vvv -c 0 info` shows the probe.
- HDMI1 (DP over USB-C, PCM 5) and HDMI2 (PCM 6) are left out: with no display attached their PCMs reject `hw_params`, which
  again makes ACP drop the profile. Revisit with a display plugged in.
- Result: sinks *Speaker* (default) and *Headphones*, sources *Internal Microphone* (default) and *Headset Microphone*, active
  profile HiFi. `pw-play` on the speaker exits cleanly; a 3 s internal-mic recording had peak 7673/32767.
