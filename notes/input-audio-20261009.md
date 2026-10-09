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

### Follow-ups

- `Headphone Jack Switch` (machine-driver pin switch) is off at boot; it is now set in the Headphones device sequences.
- `Ext_Speaker_Amp Switch` exists but writing it fails (`ASoC: DAPM unknown pin Ext_Speaker_Amp`, EINVAL) on this RT1019
  board, and a failing cset aborts the device enable, so it must not be in the UCM. The speaker path powers up from the
  route alone: during playback debugfs shows `DL0` → `I2SOUT1` → `audio-rt1019p` `SDB: On`, `Speaker: On`.
- Apps started before `pipewire-pulse` existed (Chrome) have no audio connection until restarted.
- ChromeOS's CRAS caps the speaker at -3.25 dB at 100% volume (`/etc/cras/quigon.rt1019.rt5682s/*.card_settings`,
  explicit `db_at_N` curve), likely speaker protection. Not replicated yet.

## Sleep (s2idle) and thermals

[`scripts/sleeptest.sh`](../scripts/sleeptest.sh) (RTC `rtc0`, mt6359 PMIC, `wakealarm` +30 s, then `systemctl suspend`):
suspend_stats success 1 / fail 0; ~29 s asleep; Omarchy's lock screen came up (user unlocked); wlan0 reconnected and
the laptop answered ping; Hyprland still on libmali, bar running, speaker sink present, palm filter active. Kernel log
on resume: one `mediatek-drm-dp 11b70000.edp-tx: Failed to do AUX transfer: -110` (display came back fine). Battery
drain over 30 s is below the gauge's resolution; an overnight lid-closed test is still to do. Lid → suspend uses the
logind default; Omarchy's idle: screensaver 150 s, lock 300 s (same as the other Omarchy machines).

Fanless: `cros_ec` hwmon exposes fan1–4 but all read 0 rpm with no fault; cooling devices are only cpufreq (cpu0, cpu6)
and GPU devfreq. SoC ~40–42 °C at light load.

## Hardware video decoding: not reachable from Linux Chrome

- `/dev/video5` `mtk-vcodec-dec` ("MT8189 video decoder", media device `/dev/media1`): **stateless** H.264 (`S264`),
  VP9 (`VP9F`), HEVC (`S265`); no AV1. Output (capture) format is **only `MM21`** (MediaTek 8-bit block-tiled).
- Linux Chrome only has VA-API decode (no ChromeOS-style V4L2 path). Omarchy's aarch64 repo has
  `libva-v4l2_request-avd` (VA-API on V4L2 stateless decoders, Asahi AVD fork): `vainfo` with
  `LIBVA_DRIVER_NAME=v4l2_request LIBVA_V4L2_REQUEST_VIDEO_PATH=/dev/video5 LIBVA_V4L2_REQUEST_MEDIA_PATH=/dev/media1`
  lists H.264 CB/Main/High, HEVC Main/Main10, VP9 0/2, but every decode fails at once (ffmpeg `-hwaccel vaapi`: thread
  error -1145393733) because the driver can't produce frames from `MM21`. ChromeOS's Chrome converts MM21 with its own
  image processor.
- Software cost is small anyway: ffmpeg 1080p30 10 s clip, 8 threads — VP9 3.6 CPU-s (≈0.36 core), H.264 4.2 CPU-s.
  Packages left installed (`libva-v4l2_request-avd`, `libva-utils`, `v4l-utils`) are harmless; nothing sets them up.
- **YouTube baseline, software decode (2026-10-09):** Chrome, "2020 LG OLED l The Black 4K HDR 60fps" (njX2bu-_Vw4) in an
  802×451 player. YouTube chose `vp09.00.51.08` itag 302 = **VP9 720p60** (VP9, not AV1, so the hardware decoder could
  take it). Over 30 s (part of which may have been paused): renderer 117% of a core (one renderer at 105%, the
  software VP9 decoder), GPU process 31% (libmali compositing), whole system 190% of 800%. Stats for nerds over 35.8 s
  of video: 2260 frames (~63 fps), 4 dropped. Smooth, but costs ~1.2+ cores. 1080p60 would be ~2.25× the pixels.
  Power not measured (on the charger, battery full).
- Possible later: GStreamer's `v4l2codecs` (gst-plugins-bad) handles MM21, for GStreamer-based players only.

## Quick hardware checks (2026-10-09)

- Webcam (`/dev/video0`, USB UVC `5986:2189`): MJPEG up to 1280×720; ffmpeg captured 30 frames (nothing saved).
- Bluetooth (`hci0`, btmtk/btusb on the MT7921): powers on, a 10 s scan saw 6 nearby devices.
- Touchscreen (`tc3408 1DA0:3018`, i2c-hid): works out of the box in Hyprland (user confirmed taps/scrolling).
- External display: connectors `DP-1` (USB-C) and `HDMI-A-1` present, untested (nothing attached). HDMI/DP audio still
  left out of the UCM profile.

## Lid sleep test and Wi-Fi after resume

Manual lid close: logind "Lid closed" → s2idle entry 13 s later → "Lid opened" ~30 s after, woke via `chromeos-ec` IRQ;
suspend_stats 2/0. Two problems:

- `omarchy-system-sleep-lock: suspending without a secure lock (the shell did not secure the session within 12000ms)`:
  the bar didn't confirm its lock before the inhibitor budget (logind `InhibitDelayMaxSec=15`), so it slept unlocked
  (the lock appeared on wake). Seen once with the bar on `QT_QUICK_BACKEND=software`; to investigate.
- Wi-Fi: NetworkManager brought wlan0 back as `unavailable` and made no autoconnect attempt for 76 s (the RTC test
  reconnected in ~12 s), and the 5 GHz network didn't show; the user connected to the 2.4 GHz SSID by hand. Afterwards the
  5 GHz AP was visible again (regdom US, ch 153). Fixes: `home-wifi` (5 GHz) autoconnect-priority 10 over the 2.4 GHz
  profile; [`quigon-wifi-resume`](../port/quigon/root/usr/lib/systemd/system-sleep/quigon-wifi-resume) system-sleep hook
  rescans and reconnects if wlan0 isn't connected 15 s after resume (detached; `/usr/lib/systemd/system-sleep/` because
  systemd 261 ignores `/etc`).

### Lock before sleep: Quickshell 0.3.2 regression (fixed by pinning 0.3.1)

The unlocked-sleep wasn't timing. After the first unlock (23:21:59), the bar's `lock status` read `"locked":true` while
`requested`, `sessionLocked` and `secure` were all false — but `locked` is defined in Omarchy's lock service as
`lockRequested || sessionLock.locked || sessionLock.secure`. The unlock had logged `secure=false` and `unlocked` but never
`session-locked=false`: `WlSessionLock`'s lock-state change never arrived, so the binding stayed stale. The IPC `lock()`
then saw `root.locked` and returned "ok" without locking, and `omarchy-system-sleep-lock` polled for `secure` until its
12 s budget ran out. Every lock after the first unlock silently failed until the bar restarted.

The XPS 13 (Omarchy rc, **Quickshell 0.3.1**) logs `secure=false`, `session-locked=false` ×2, `unlocked` and returns to
`locked:false`. The Chromebook had **0.3.2-2** from Omarchy's aarch64 edge repo (built 2026-10-08). Downgraded to ALARM
`extra/quickshell 0.3.1-1` and pinned (`IgnorePkg = quickshell` in pacman.conf and the guard's known-good copy;
quigon-doctor checks it). User test: lock → unlock → lock → unlock now logs exactly the XPS sequence twice and ends at
`locked:false`. Worth reporting upstream (Quickshell 0.3.2 / Omarchy edge).

Upstream (checked 2026-10-09, not re-filed — already fully reported): Quickshell
[#1230](https://github.com/quickshell-mirror/quickshell/issues/1230) (`WlSessionLock::unlock()` checks `isLocked()` after
releasing, so `lockStateChanged` never fires; a comment bisects it to afb2c27 "wayland/lock: guard against reentrancy
during surface creation" — the 0.3.1 tag still notifies on unlock), and Omarchy
[#14588](https://github.com/omacom/omarchy/issues/14588) (same self-contradictory `lock status`; a comment gives the 0.3.2
root cause, a tested patch, and "downgrade to the release before 0.3.2"). Related: Omarchy #10299. Remove the
`IgnorePkg = quickshell` pin once a release with the fix lands.
