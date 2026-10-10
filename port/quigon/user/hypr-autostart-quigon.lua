-- quigon additions to ~/.config/hypr/autostart.lua (append; quigon-doctor checks for them).

-- quigon: notify if the GPU boot guard switched this session to software rendering.
o.exec_on_start("quigon-gpu-notify")

-- quigon: lid close locks and blanks (Hyprland switch bindings do not fire on this machine).
o.exec_on_start("/usr/local/libexec/quigon/quigon-lid-watch")
