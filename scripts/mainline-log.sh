#!/bin/bash
# mainline-log.sh [all]: after a boot-once test, show what the test kernel logged (pstore console of the previous
# boot): the QM: lines from its init, then errors/warnings, then (with "all") everything.
c=/sys/fs/pstore/console-ramoops-0
[[ -r $c ]] || { echo "no console-ramoops-0"; exit 1; }
echo "== $(head -c 300 $c | grep -a -o 'Linux version [^ ]* ' | head -1) ($(wc -l < $c) lines, $(stat -c %y $c | cut -c1-19))"
grep -a "QM:" $c | sed 's/^.*QM: /QM: /'
echo "== errors/warnings:"; grep -a -i -E "error|fail|warn|unable|panic|oops|bug:|probe of .* failed|deferred" $c | grep -a -v "QM:" | head -${LINES_MAX:-60}
[[ ${1:-} == all ]] && { echo "== full:"; cat $c; }
ls -la /sys/fs/pstore/
