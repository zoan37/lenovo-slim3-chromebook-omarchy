-- quigon additions to ~/.config/hypr/hyprland.lua (append at the end; quigon-doctor checks for them).

-- quigon (Lenovo Chromebook): software cursor only if /etc/quigon/sw-cursor exists. Early mainline builds drew the
-- hardware cursor as long white lines; with the display fixes since (2026-10-10) the hardware cursor works.
do
  local f = io.open("/etc/quigon/sw-cursor")
  if f then
    f:close()
    hl.config({ cursor = { no_hardware_cursors = true } })
  end
end
