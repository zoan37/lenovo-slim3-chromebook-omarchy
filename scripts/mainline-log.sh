#!/bin/bash
# mainline-log.sh [all]: after a boot-once test, show what the test kernel logged: the pstore console of the
# previous boot (QM: lines from its init, then errors/warnings, then with "all" everything) and, if the test froze
# hard (power-off wipes pstore), the hang-proof disk log its init wrote (/var/lib/quigon/mainline-blklog). The disk
# log is cleared after it is shown, so each round starts empty.
b=/var/lib/quigon/mainline-blklog
if [[ $(head -c 4 $b 2>/dev/null | tr -d "\0") == QBLK ]]; then
  echo "== disk log: $(head -1 $b)"
  tr -d '\0' < $b | grep -a -E "QM:|QBLK" | sed 's/^.*QM: /QM: /' | tail -n +2
  echo "== disk log, last kernel messages:"; tr -d '\0' < $b | grep -a -v "QM:" | tail -${LINES_MAX:-40}
  [[ ${1:-} == all ]] && { echo "== disk log, full:"; tr -d '\0' < $b; }
  dd if=/dev/zero of=$b bs=1M count=4 conv=notrunc,fsync status=none
fi
c=/sys/fs/pstore/console-ramoops-0
[[ -r $c ]] || { echo "no console-ramoops-0"; exit 1; }
echo "== $(head -c 300 $c | grep -a -o 'Linux version [^ ]* ' | head -1) ($(wc -l < $c) lines, $(stat -c %y $c | cut -c1-19))"
grep -a "QM:" $c | sed 's/^.*QM: /QM: /'
echo "== errors/warnings:"; grep -a -i -E "error|fail|warn|unable|panic|oops|bug:|probe of .* failed|deferred" $c | grep -a -v "QM:" | head -${LINES_MAX:-60}
[[ ${1:-} == all ]] && { echo "== full:"; cat $c; }
ls -la /sys/fs/pstore/
