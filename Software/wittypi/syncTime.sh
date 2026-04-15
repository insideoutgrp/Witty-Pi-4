#!/bin/bash
# file: syncTime.sh
#
# Periodically syncs system clock from network time and writes to RTC.
# Intended to be called by cron, e.g. every 6 hours.
#

cur_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$cur_dir/utilities.sh"

TIME_UNKNOWN=0

if [ $(is_mc_connected) -ne 1 ]; then
  log 'Time sync: Witty Pi not connected, skipping.'
  exit 1
fi

if has_internet ; then
  log 'Time sync: Internet available, syncing...'
  net_to_system
  system_to_rtc
  log "Time sync: Complete. RTC set to $(date -u +'%Y-%m-%d %H:%M:%S UTC')"
else
  log 'Time sync: No internet, skipping.'
fi
