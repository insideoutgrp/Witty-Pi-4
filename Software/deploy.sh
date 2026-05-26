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

  # copy updated scripts atomically: write to a .new file then mv into
  # place. If a reboot or kill interrupts the copy, the daemon will still
  # find the previous (valid) version on disk instead of a half-written
  # file that fails syntax checks at the next source.
  for f in $UPDATE_FILES; do
    if [ -f "$SRC_DIR/wittypi/$f" ]; then
      cp "$SRC_DIR/wittypi/$f" "$WITTYPI_DIR/$f.new"
      chmod +x "$WITTYPI_DIR/$f.new"
      # syntax check before swapping in - protects against bad pushes
      if bash -n "$WITTYPI_DIR/$f.new" 2>/dev/null; then
        mv "$WITTYPI_DIR/$f.new" "$WITTYPI_DIR/$f"
        echo "  Updated $f"
      else
        rm -f "$WITTYPI_DIR/$f.new"
        echo "  SKIPPED $f (syntax check failed - keeping previous version)"
        ((ERR++)) 2>/dev/null || true
      fi
    fi
  done

  # update schedules
  if [ -d "$SRC_DIR/../Schedules" ]; then
    echo ''
    echo '>>> Updating schedules'
    mkdir -p "$WITTYPI_DIR/schedules"
    cp "$SRC_DIR/../Schedules/"*.wpi "$WITTYPI_DIR/schedules/" 2>/dev/null
    # remove retired / mislabeled schedules from existing devices
    rm -f "$WITTYPI_DIR/schedules/1h_weekday_247_weekend.wpi"
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

  # restart daemon: kill the daemon and ANY backgrounded child (runScript.sh)
  # that may still be writing to I2C alarm registers. Two concurrent writers
  # could otherwise leave registers in an inconsistent state.
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
  # also kill any orphaned runScript.sh from the previous daemon's background launch
  pkill -f "$WITTYPI_DIR/runScript.sh" 2>/dev/null && echo '  Stopped any active runScript.sh.'
  sleep 1
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

  # Enable the Raspberry Pi BCM2835 hardware watchdog via systemd.
  # If the kernel ever hangs, the SoC watchdog will force a hard reboot
  # after 30 seconds. This is the last line of defence against frozen Pis
  # that the WittyPi firmware can't detect.
  echo ''
  echo '>>> Enabling kernel hardware watchdog (30s timeout)'
  if [ -f /etc/systemd/system.conf ]; then
    if grep -qE '^\s*RuntimeWatchdogSec=30\b' /etc/systemd/system.conf; then
      echo '  Watchdog already enabled.'
    else
      # remove any existing line then append
      sed -i.bak '/^#*\s*RuntimeWatchdogSec=/d' /etc/systemd/system.conf
      echo 'RuntimeWatchdogSec=30' >> /etc/systemd/system.conf
      systemctl daemon-reexec 2>/dev/null || true
      echo '  Watchdog enabled (effective on next boot).'
    fi
  else
    echo '  /etc/systemd/system.conf not found, skipping.'
  fi

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
  # install.sh installs into ./wittypi relative to its working directory, so
  # it must run from the target user's home -- NOT from inside the source
  # checkout (which ships its own wittypi/ folder and would be mistaken for
  # an existing install). WITTYPI_SRC points install.sh at the real source.
  TARGET_USER="${SUDO_USER:-$(id -un)}"
  TARGET_HOME="$(eval echo "~${TARGET_USER}")"
  if [ -z "$TARGET_HOME" ] || [ ! -d "$TARGET_HOME" ]; then
    TARGET_HOME='/home/pi'
  fi
  echo ">>> Installing Witty Pi software into $TARGET_HOME/wittypi"
  ( cd "$TARGET_HOME" && WITTYPI_SRC="$SRC_DIR/wittypi" bash "$SRC_DIR/install.sh" )
fi

# cleanup
rm -rf "$TMP_DIR"
