-- quigon additions to ~/.config/hypr/hyprland.lua (append at the end; quigon-doctor checks for them).

-- quigon (Lenovo Chromebook), mainline kernel only (release contains "quigon"): mediatek-drm's hardware cursor
-- draws long white lines instead of the pointer, so use Hyprland's software cursor there.
do
  local f = io.open("/proc/sys/kernel/osrelease")
  local release = f and f:read("*l") or ""
  if f then f:close() end
  if release:find("quigon", 1, true) then
    hl.config({ cursor = { no_hardware_cursors = true } })
  end
end
