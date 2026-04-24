#!/bin/bash
# file: deploy.sh
#
# One-liner deployment script for Witty Pi 4 DST fix (v4.24).
# Run on a Pi with:
#   curl -sSL https://raw.githubusercontent.com/insideoutgrp/Witty-Pi-4/main/Software/deploy.sh | sudo bash
#

set -e

if [ "$(id -u)" != 0 ]; then
  echo 'Sorry, you need to run this script with sudo'
  exit 1
fi

REPO_URL="https://github.com/insideoutgrp/Witty-Pi-4"
BRANCH="main"
TMP_DIR=$(mktemp -d)

echo '================================================================================'
echo '|                                                                              |'
echo '|          Witty Pi 4 DST Fix (v4.24) - Remote Deploy                          |'
echo '|                                                                              |'
echo '================================================================================'
echo ''

# detect existing installation
WITTYPI_DIR=""
if [ -d "$HOME/wittypi" ]; then
  WITTYPI_DIR="$HOME/wittypi"
elif [ -d "/home/pi/wittypi" ]; then
  WITTYPI_DIR="/home/pi/wittypi"
elif [ ! -z "$SUDO_USER" ] && [ -d "$(eval echo ~$SUDO_USER)/wittypi" ]; then
  WITTYPI_DIR="$(eval echo ~$SUDO_USER)/wittypi"
fi

# download the repo
echo ">>> Downloading from $REPO_URL"
wget -q "$REPO_URL/archive/refs/heads/$BRANCH.tar.gz" -O "$TMP_DIR/wittypi.tar.gz" || {
  echo 'Error: Failed to download. Check your internet connection.'
  rm -rf "$TMP_DIR"
  exit 1
}
tar -xzf "$TMP_DIR/wittypi.tar.gz" -C "$TMP_DIR"
SRC_DIR="$TMP_DIR/Witty-Pi-4-$BRANCH/Software"
echo '  Done.'
echo ''

if [ ! -z "$WITTYPI_DIR" ] && [ -f "$WITTYPI_DIR/utilities.sh" ]; then
  # --- UPDATE existing installation ---
  CURRENT_VER=$(grep "SOFTWARE_VERSION=" "$WITTYPI_DIR/utilities.sh" | head -1 | grep -o "'[^']*'" | tr -d "'")
  TARGET_VER=$(grep "SOFTWARE_VERSION=" "$SRC_DIR/wittypi/utilities.sh" | head -1 | grep -o "'[^']*'" | tr -d "'")
  echo ">>> Existing installation found at $WITTYPI_DIR (v${CURRENT_VER:-unknown})"

  if [ "$CURRENT_VER" = "$TARGET_VER" ]; then
    echo "  Already at v${TARGET_VER}, no update needed."
    rm -rf "$TMP_DIR"
    exit 0
  fi

  echo "  Updating to v${TARGET_VER}..."
  UPDATE_FILES="utilities.sh daemon.sh runScript.sh wittyPi.sh syncTime.sh checkInternet.sh"

  # backup
  BACKUP_DIR="$WITTYPI_DIR/backup_v${CURRENT_VER:-old}_$(date +%Y%m%d_%H%M%S)"
  echo "  Backup: $BACKUP_DIR"
  mkdir -p "$BACKUP_DIR"
  for f in $UPDATE_FILES; do
    [ -f "$WITTYPI_DIR/$f" ] && cp "$WITTYPI_DIR/$f" "$BACKUP_DIR/$f"
  done

  # copy updated scripts
  for f in $UPDATE_FILES; do
    if [ -f "$SRC_DIR/wittypi/$f" ]; then
      cp "$SRC_DIR/wittypi/$f" "$WITTYPI_DIR/$f"
      chmod +x "$WITTYPI_DIR/$f"
      echo "  Updated $f"
    fi
  done

  # update schedules
  if [ -d "$SRC_DIR/../Schedules" ]; then
    echo ''
    echo '>>> Updating schedules'
    mkdir -p "$WITTYPI_DIR/schedules"
    cp "$SRC_DIR/../Schedules/"*.wpi "$WITTYPI_DIR/schedules/" 2>/dev/null
    echo "  Copied $(ls "$SRC_DIR/../Schedules/"*.wpi 2>/dev/null | wc -l | tr -d ' ') schedule(s) to $WITTYPI_DIR/schedules/"
  fi

  # also update install.sh in parent dir
  INSTALL_DIR="$(dirname "$WITTYPI_DIR")"
  if [ -f "$SRC_DIR/install.sh" ]; then
    cp "$SRC_DIR/install.sh" "$INSTALL_DIR/install.sh" 2>/dev/null || true
  fi

  # fix ownership
  if [ ! -z "$SUDO_USER" ]; then
    chown -R $SUDO_USER:$(id -g -n $SUDO_USER) "$WITTYPI_DIR" 2>/dev/null
  fi

  # restart daemon
  echo ''
  echo '>>> Restarting daemon'
  if [ -f /var/run/wittypi_daemon.pid ]; then
    OLD_PID=$(cat /var/run/wittypi_daemon.pid 2>/dev/null)
    if [ ! -z "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
      kill "$OLD_PID" 2>/dev/null
      sleep 1
      echo '  Stopped old daemon.'
    fi
  fi
  "$WITTYPI_DIR/daemon.sh" &
  sleep 1
  DAEMON_PID=$(ps --ppid $! -o pid= 2>/dev/null)
  if [ ! -z "$DAEMON_PID" ]; then
    echo "$DAEMON_PID" > /var/run/wittypi_daemon.pid
    echo "  Daemon restarted (PID: $DAEMON_PID)."
  else
    echo '  Daemon will start on next reboot.'
  fi

  # immediate time sync to migrate RTC to UTC
  echo ''
  echo '>>> Syncing time and migrating RTC to UTC'
  "$WITTYPI_DIR/syncTime.sh" >> "$WITTYPI_DIR/wittyPi.log" 2>&1
  if [ $? -eq 0 ]; then
    echo '  RTC migrated to UTC.'
  else
    echo '  No internet - RTC will be migrated on next sync.'
  fi

  # set up cron job for periodic time sync
  echo ''
  echo '>>> Setting up periodic time sync'
  CRON_CMD="$WITTYPI_DIR/syncTime.sh >> $WITTYPI_DIR/wittyPi.log 2>&1"
  # remove any existing syncTime cron entry then add the current one
  (crontab -l 2>/dev/null | grep -vF 'syncTime.sh'; echo "*/15 * * * * $CRON_CMD") | crontab -
  echo '  Cron job set: sync time every 15 minutes.'

  # set up cron job for internet connectivity check (offset from syncTime)
  echo ''
  echo '>>> Setting up internet connectivity check'
  NET_CHECK_CMD="$WITTYPI_DIR/checkInternet.sh >> $WITTYPI_DIR/wittyPi.log 2>&1"
  (crontab -l 2>/dev/null | grep -vF 'checkInternet.sh'; echo "7,22,37,52 * * * * $NET_CHECK_CMD") | crontab -
  echo '  Cron job set: check internet every 15 min (at :07/:22/:37/:52).'
  # ensure the script is present and executable on device
  chmod +x "$WITTYPI_DIR/checkInternet.sh" 2>/dev/null

  echo ''
  echo '================================================================================'
  echo "  Update complete! v${CURRENT_VER} -> v${TARGET_VER}"
  echo ''
  echo '  RTC will be migrated to UTC automatically.'
  echo '  If offline, run wittyPi.sh and choose option 1 after verifying system time.'
  echo ''
  echo "  Rollback: sudo cp $BACKUP_DIR/* $WITTYPI_DIR/ && sudo reboot"
  echo '================================================================================'

else
  # --- FRESH installation ---
  echo '>>> No existing installation found. Running full install...'
  cd "$SRC_DIR"
  bash install.sh
fi

# cleanup
rm -rf "$TMP_DIR"
