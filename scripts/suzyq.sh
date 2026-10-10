#!/bin/bash
# suzyq.sh: the quigon's debug consoles over a SuzyQ (CCD) cable, on the host it's plugged into.
#   suzyq.sh list                    which /dev/ttyUSB* is which console
#   suzyq.sh log <ap|ec|gsc> [sec]   print what the console says for <sec> seconds (default: until Ctrl+C)
#   suzyq.sh cmd <ec|gsc|ap> <text>  type one command into a console and print the reply (5 s)
#   suzyq.sh reset                   hard-reset the Chromebook (GSC `ecrst pulse`: EC and AP restart; needs CCD open
#                                    with RebootECAP); asks first
# The cable answers on USB-C port 0 with the plug in reverse orientation only (see notes/suzyq-20261010.md).
# Interactive sessions: `tio /dev/ttyUSB2` (or picocom/minicom) once installed. User must be in the uucp group.
set -euo pipefail
dev() {  # console name (Shell, AP, EC, FPMCU) -> /dev/ttyUSBn, from the GSC's USB interface strings
  local want=$1 t
  for t in /sys/class/tty/ttyUSB*; do
    [[ -e $t ]] || continue
    [[ $(cat "$(readlink -f "$t/device/..")/interface" 2>/dev/null) == "$want" ]] && { echo "/dev/${t##*/}"; return; }
  done
  echo "no $want console: is the SuzyQ in USB-C port 0, plug reversed?" >&2; exit 1
}
name() { case $1 in ap) echo AP ;; ec) echo EC ;; gsc|shell|ti50) echo Shell ;; fp|fpmcu) echo FPMCU ;; *) echo "unknown console $1" >&2; exit 2 ;; esac; }
open_tty() { stty -F "$1" 115200 raw -echo 2>/dev/null || true; }
case ${1:-} in
  list)
    for t in /sys/class/tty/ttyUSB*; do [[ -e $t ]] && echo "/dev/${t##*/}: $(cat "$(readlink -f "$t/device/..")/interface")"; done
    lsusb | grep -i 18d1 || echo "no GSC on USB" ;;
  log)
    d=$(dev "$(name "${2:?ap|ec|gsc}")"); open_tty "$d"
    if [[ -n ${3:-} ]]; then timeout "$3" cat "$d" | tr -d '\r' || true; else tr -d '\r' < "$d"; fi ;;
  cmd)
    d=$(dev "$(name "${2:?ec|gsc|ap}")"); open_tty "$d"; o=$(mktemp)
    timeout 5 cat "$d" > "$o" & sleep 0.3
    printf '\r%s\r' "${3:?command}" > "$d"; wait || true
    tr -d '\r' < "$o"; rm -f "$o" ;;
  reset)
    read -r -p "Hard-reset the Chromebook now (unsaved work is lost)? [y/N] " a; [[ $a == [yY] ]] || exit 0
    d=$(dev Shell); open_tty "$d"; printf '\recrst pulse\r' > "$d"; echo "sent: ecrst pulse" ;;
  *) sed -n '2,/^set -euo/p' "$0" | sed '$d; s/^# \{0,1\}//'; exit 2 ;;
esac
