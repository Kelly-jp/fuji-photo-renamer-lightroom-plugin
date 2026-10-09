#!/bin/sh
# The caller supplies only an owned work directory and a trusted executable.
set -u
umask 077
executable=$1
work_dir=$2
limit=$3
case "$limit" in ''|*[!0-9]*) exit 125 ;; esac
if [ "$limit" -lt 1 ] || [ "$limit" -gt 120 ]; then exit 125; fi

"$executable" -config '' -charset filename=UTF8 -@ "$work_dir/arguments.txt" \
    > "$work_dir/stdout.json" 2> "$work_dir/stderr.txt" &
tool_pid=$!

# A fixed script avoids interpreting photo names or metadata as shell code.
(
    sleeper_pid=''
    trap 'if [ -n "$sleeper_pid" ]; then kill "$sleeper_pid" 2>/dev/null || :; fi; exit 0' TERM
    sleep "$limit" &
    sleeper_pid=$!
    wait "$sleeper_pid"
    if kill -0 "$tool_pid" 2>/dev/null; then
        printf 'timeout\n' > "$work_dir/timed-out.txt"
        kill -TERM "$tool_pid" 2>/dev/null || exit 0
        sleep 1 &
        sleeper_pid=$!
        wait "$sleeper_pid"
        kill -KILL "$tool_pid" 2>/dev/null || :
    fi
) &
watchdog_pid=$!

wait "$tool_pid"
status=$?
kill "$watchdog_pid" 2>/dev/null || :
wait "$watchdog_pid" 2>/dev/null || :
if [ -f "$work_dir/timed-out.txt" ]; then status=124; fi
printf '%s\n' "$status" > "$work_dir/exit-code.txt"
exit "$status"
