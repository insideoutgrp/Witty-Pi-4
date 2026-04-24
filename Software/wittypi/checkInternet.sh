#!/bin/bash
# file: checkInternet.sh
#
# Pings a remote server to check internet connectivity. If this fails
# for $FAIL_THRESHOLD consecutive runs, logs a warning and reboots the
# Raspberry Pi. Intended to be called by cron, at an offset schedule
# (not on-the-hour) to avoid clashing with other periodic jobs.
#

cur_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$cur_dir/utilities.sh"

TIME_UNKNOWN=0

# configurable
readonly PING_TARGETS=('8.8.8.8' '1.1.1.1' 'www.google.com')
readonly FAIL_THRESHOLD=3
readonly STATE_FILE="$cur_dir/.net_fail_count"

# load previous failure count (0 if first run or reset)
fail_count=0
if [ -f "$STATE_FILE" ]; then
  fail_count=$(cat "$STATE_FILE" 2>/dev/null || echo 0)
  [[ "$fail_count" =~ ^[0-9]+$ ]] || fail_count=0
fi

# try each ping target; success on any clears the counter
online=0
for target in "${PING_TARGETS[@]}"; do
  if ping -c 1 -W 3 "$target" >/dev/null 2>&1; then
    online=1
    break
  fi
done

if [ $online -eq 1 ]; then
  if [ "$fail_count" -gt 0 ]; then
    log "Internet check: connectivity restored after $fail_count failed attempt(s)."
  fi
  echo 0 > "$STATE_FILE"
else
  fail_count=$((fail_count + 1))
  echo "$fail_count" > "$STATE_FILE"
  log "Internet check: FAILED ($fail_count/$FAIL_THRESHOLD). Targets unreachable: ${PING_TARGETS[*]}"

  if [ "$fail_count" -ge "$FAIL_THRESHOLD" ]; then
    log "Internet check: reached $FAIL_THRESHOLD consecutive failures. Rebooting..."
    # reset counter so we don't reboot loop on next boot if still offline
    echo 0 > "$STATE_FILE"
    sync
    shutdown -r now
  fi
fi
