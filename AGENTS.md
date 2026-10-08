# Notes for coding agents

This repo is private for now and may be made public later, so write everything as if it were public.

## Privacy

- No real names, login names, emails or home paths with a username. Use `~` or `$HOME`.
- No device identifiers: the full ChromeOS **HWID** (call the board `quigon`), serial numbers, MAC addresses,
  disk/partition UUIDs from the internal drive, Wi-Fi network names or passphrases, public IPs.
  Private LAN addresses (`192.168.x.x`) are fine.
- Raw dumps (kernel partition, firmware, logs with identifiers) go in `private/` or `artifacts/` (gitignored).

Scan before committing:

```sh
git diff --cached -U0 | grep -n -i -E '/home/[a-z]|hwid|psk=|passphrase'
```

## Working with the device

`scripts/bridge/` is a LAN command bridge: `bridge.py <laptop-ip>` serves on port 53317 (allowed by Omarchy's
ufw for LocalSend); the Chromebook runs `curl -s http://<laptop-ip>:53317/<token>/agent.sh | sudo bash` from the
developer-mode console (Ctrl+Alt+⟳, user `chronos`), then `scripts/bridge/cb '<commands>'` runs them as root on
the device and prints the output. Inside a command, `$B` is the bridge URL: upload with `curl -T file "$B/up/name"`,
download with `curl -o file "$B/files/name"`.

## Hardware gotchas

- The **power button is on the side**. The top-right keyboard key is a lock key.
- Recovery mode: hold Esc + Refresh (⟳), press the side power button.
- If the laptop goes completely dead (no response even on the charger), use the pinhole on the bottom:
  charger unplugged, hold ~10 s (no click), then plug the charger in.
- The ChromeOS kernel has no VT or fbcon (`/dev/tty1` and `/dev/fb*` don't exist; ChromeOS uses frecon),
  so a booted Linux shows a black screen until something drives DRM. Debug over the network and from logs.
