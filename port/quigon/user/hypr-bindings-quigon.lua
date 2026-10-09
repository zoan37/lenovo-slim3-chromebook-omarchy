-- quigon: Chromebook top row. Bound by xkb keycode (evdev + 8) because some have no stable keysym.
o.bind("code:380", "Full screen (top-row key)", hl.dsp.window.fullscreen({ mode = "fullscreen" }))  -- KEY_FULL_SCREEN
o.bind("code:128", "Apps menu (top-row overview key)", "omarchy-menu toggle apps")                -- KEY_SCALE
o.bind("code:150", "Lock screen (top-right lock key)", "omarchy-system-lock")                     -- KEY_SLEEP
if o.cmd_present("voxtype") then
  o.bind("code:594", "Toggle dictation (top-row dictate key)", "voxtype record toggle")            -- KEY_DICTATE
end
