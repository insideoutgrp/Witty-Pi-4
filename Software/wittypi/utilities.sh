#!/bin/bash
# file: utilities.sh
#
# This script provides some useful utility functions
#

export LC_ALL=en_GB.UTF-8

if [ -z ${I2C_MC_ADDRESS+x} ]; then
  readonly I2C_MC_ADDRESS=0x08

  readonly I2C_BUS=1

  readonly I2C_ID=0
  readonly I2C_VOLTAGE_IN_I=1
  readonly I2C_VOLTAGE_IN_D=2
  readonly I2C_VOLTAGE_OUT_I=3
  readonly I2C_VOLTAGE_OUT_D=4
  readonly I2C_CURRENT_OUT_I=5
  readonly I2C_CURRENT_OUT_D=6
  readonly I2C_POWER_MODE=7
  readonly I2C_LV_SHUTDOWN=8
  readonly I2C_ALARM1_TRIGGERED=9
  readonly I2C_ALARM2_TRIGGERED=10
  readonly I2C_ACTION_REASON=11
  readonly I2C_FW_REVISION=12

  readonly I2C_CONF_ADDRESS=16
  readonly I2C_CONF_DEFAULT_ON=17
  readonly I2C_CONF_PULSE_INTERVAL=18
  readonly I2C_CONF_LOW_VOLTAGE=19
  readonly I2C_CONF_BLINK_LED=20
  readonly I2C_CONF_POWER_CUT_DELAY=21
  readonly I2C_CONF_RECOVERY_VOLTAGE=22
  readonly I2C_CONF_DUMMY_LOAD=23
  readonly I2C_CONF_ADJ_VIN=24
  readonly I2C_CONF_ADJ_VOUT=25
  readonly I2C_CONF_ADJ_IOUT=26

  readonly I2C_CONF_SECOND_ALARM1=27
  readonly I2C_CONF_MINUTE_ALARM1=28
  readonly I2C_CONF_HOUR_ALARM1=29
  readonly I2C_CONF_DAY_ALARM1=30
  readonly I2C_CONF_WEEKDAY_ALARM1=31

  readonly I2C_CONF_SECOND_ALARM2=32
  readonly I2C_CONF_MINUTE_ALARM2=33
  readonly I2C_CONF_HOUR_ALARM2=34
  readonly I2C_CONF_DAY_ALARM2=35
  readonly I2C_CONF_WEEKDAY_ALARM2=36

  readonly I2C_CONF_RTC_OFFSET=37
  readonly I2C_CONF_RTC_ENABLE_TC=38
  readonly I2C_CONF_FLAG_ALARM1=39
  readonly I2C_CONF_FLAG_ALARM2=40

  readonly I2C_CONF_IGNORE_POWER_MODE=41
  readonly I2C_CONF_IGNORE_LV_SHUTDOWN=42

  readonly I2C_CONF_BELOW_TEMP_ACTION=43
  readonly I2C_CONF_BELOW_TEMP_POINT=44
  readonly I2C_CONF_OVER_TEMP_ACTION=45
  readonly I2C_CONF_OVER_TEMP_POINT=46
  readonly I2C_CONF_DEFAULT_ON_DELAY=47

  readonly I2C_CONF_MISC=48
  readonly I2C_CONF_GUARANTEED_WAKE=49

  readonly I2C_LM75B_TEMPERATURE=50
  readonly I2C_LM75B_CONF=51
  readonly I2C_LM75B_THYST=52
  readonly I2C_LM75B_TOS=53

  readonly I2C_RTC_CTRL1=54
  readonly I2C_RTC_CTRL2=55
  readonly I2C_RTC_OFFSET=56
  readonly I2C_RTC_RAM_BYTE=57
  readonly I2C_RTC_SECONDS=58
  readonly I2C_RTC_MINUTES=59
  readonly I2C_RTC_HOURS=60
  readonly I2C_RTC_DAYS=61
  readonly I2C_RTC_WEEKDAYS=62
  readonly I2C_RTC_MONTHS=63
  readonly I2C_RTC_YEARS=64
  readonly I2C_RTC_SECOND_ALARM=65
  readonly I2C_RTC_MINUTE_ALARM=66
  readonly I2C_RTC_HOUR_ALARM=67
  readonly I2C_RTC_DAY_ALARM=68
  readonly I2C_RTC_WEEKDAY_ALARM=69
  readonly I2C_RTC_TIMER_VALUE=70
  readonly I2C_RTC_TIMER_MODE=71

  readonly HALT_PIN=4    # halt by GPIO-4 (BCM naming)
  readonly SYSUP_PIN=17  # output SYS_UP signal on GPIO-17 (BCM naming)
  readonly CHRG_PIN=5    # input to detect charging status
  readonly STDBY_PIN=6   # input to detect standby status

  readonly INTERNET_SERVER='http://google.com' # check network accessibility and get network time

  # reasons for startup/shutdown
  readonly REASON_ALARM1='0x01'
  readonly REASON_ALARM2='0x02'
  readonly REASON_CLICK='0x03'
  readonly REASON_LOW_VOLTAGE='0x04'
  readonly REASON_VOLTAGE_RESTORE='0x05'
  readonly REASON_OVER_TEMPERATURE='0x06'
  readonly REASON_BELOW_TEMPERATURE='0x07'
  readonly REASON_ALARM1_DELAYED='0x08'
  readonly REASON_USB_5V_CONNECTED='0x09'
  readonly REASON_POWER_CONNECTED='0x0a'
  readonly REASON_REBOOT='0x0b'
  readonly REASON_GUARANTEED_WAKE='0x0c'

  # config file
  if [ "$(lsb_release -si)" == "Ubuntu" ]; then
    # Ubuntu
    readonly BOOT_CONFIG_FILE="/boot/firmware/usercfg.txt"
  else
    # Raspberry Pi OS ("$(lsb_release -si)" == "Debian") and others
    readonly BOOT_CONFIG_FILE="/boot/config.txt"
  fi

  TIME_UNKNOWN=0

  SOFTWARE_VERSION='4.37'

  readonly LOCAL_TZ='Europe/London'
fi


one_wire_confliction()
{
  if [[ $HALT_PIN -eq 4 ]]; then
    if grep -qe "^\s*dtoverlay=w1-gpio\s*$" ${BOOT_CONFIG_FILE}; then
      return 0
    fi
    if grep -qe "^\s*dtoverlay=w1-gpio-pullup\s*$" ${BOOT_CONFIG_FILE}; then
      return 0
    fi
  fi
  if grep -qe "^\s*dtoverlay=w1-gpio,gpiopin=$HALT_PIN\s*$" ${BOOT_CONFIG_FILE}; then
    return 0
  fi
  if grep -qe "^\s*dtoverlay=w1-gpio-pullup,gpiopin=$HALT_PIN\s*$" ${BOOT_CONFIG_FILE}; then
    return 0
  fi
  return 1
}

has_internet()
{
  curl -s --head --connect-timeout 3 "$INTERNET_SERVER" > /dev/null
  return $?
}

get_network_timestamp()
{
  local t=$(curl -sI --connect-timeout 3 "$INTERNET_SERVER" | grep -i "^Date:" | sed 's/Date: //Ig' | tr -d '\r')
  if [ -n "$t" ]; then
    date -d "$t" +%s 2>/dev/null || echo -1
  else
    echo -1
  fi
}

is_mc_connected()
{
  local result=$(i2cdetect -y ${I2C_BUS})
  if [[ $result == *"$(printf '%02x' $I2C_MC_ADDRESS)"* ]] ; then
    echo 1
  else
    echo 0
  fi
}

get_pi_model()
{
  IFS= read -r -d '' model </proc/device-tree/model
  echo $model;
}

get_os()
{
  echo $(hostnamectl | grep 'Operating System:' | sed 's/.*Operating System: //')
}

get_kernel()
{
  echo $(uname -sr)
}

get_arch()
{
  echo $(dpkg --print-architecture)
}

get_sys_time()
{
  echo $(TZ=$LOCAL_TZ date +'%Y-%m-%d %H:%M:%S %Z')
}

get_sys_timestamp()
{
  echo $(date +%s)
}

rtc_has_bad_time()
{
  year=$(i2c_read ${I2C_BUS} $I2C_MC_ADDRESS $I2C_RTC_YEARS)
  if [[ $year -eq 0 ]]; then
    echo 1
  else
    echo 0
  fi
}

get_rtc_timestamp()
{
  sec=$(bcd2dec $((0x7F&$(i2c_read ${I2C_BUS} $I2C_MC_ADDRESS $I2C_RTC_SECONDS))))
  min=$(bcd2dec $(i2c_read ${I2C_BUS} $I2C_MC_ADDRESS $I2C_RTC_MINUTES))
  hour=$(bcd2dec $(i2c_read ${I2C_BUS} $I2C_MC_ADDRESS $I2C_RTC_HOURS))
  date=$(bcd2dec $(i2c_read ${I2C_BUS} $I2C_MC_ADDRESS $I2C_RTC_DAYS))
  month=$(bcd2dec $(i2c_read ${I2C_BUS} $I2C_MC_ADDRESS $I2C_RTC_MONTHS))
  year=$(bcd2dec $(i2c_read ${I2C_BUS} $I2C_MC_ADDRESS $I2C_RTC_YEARS))
  echo $(date -u --date="$year-$month-$date $hour:$min:$sec" +%s)
}

get_rtc_time()
{
  local rtc_ts=$(get_rtc_timestamp)
  if [ "$rtc_ts" == "" ] ; then
    echo 'N/A'
  else
    echo $(TZ=$LOCAL_TZ date +'%Y-%m-%d %H:%M:%S %Z' -d @$rtc_ts)
  fi
}

calc()
{
  awk "BEGIN { print $*}";
}

bcd2dec()
{
  local result=$(($1/16*10+($1&0xF)))
  echo $result
}

dec2bcd()
{
  local result=$((10#$1/10*16+(10#$1%10)))
  echo $result
}

dec2hex()
{
  printf "0x%02x" $1
}

hex2dec()
{
  printf "%d" $1
}

get_startup_time()
{
  sec=$(bcd2dec $(i2c_read ${I2C_BUS} $I2C_MC_ADDRESS $I2C_CONF_SECOND_ALARM1))
  min=$(bcd2dec $(i2c_read ${I2C_BUS} $I2C_MC_ADDRESS $I2C_CONF_MINUTE_ALARM1))
  hour=$(bcd2dec $(i2c_read ${I2C_BUS} $I2C_MC_ADDRESS $I2C_CONF_HOUR_ALARM1))
  date=$(bcd2dec $(i2c_read ${I2C_BUS} $I2C_MC_ADDRESS $I2C_CONF_DAY_ALARM1))
  printf '%02d %02d:%02d:%02d\n' $date $hour $min $sec
}

set_startup_time()
{
  sec=$(dec2bcd $4)
  i2c_write ${I2C_BUS} $I2C_MC_ADDRESS $I2C_CONF_SECOND_ALARM1 $sec
  min=$(dec2bcd $3)
  i2c_write ${I2C_BUS} $I2C_MC_ADDRESS $I2C_CONF_MINUTE_ALARM1 $min
  hour=$(dec2bcd $2)
  i2c_write ${I2C_BUS} $I2C_MC_ADDRESS $I2C_CONF_HOUR_ALARM1 $hour
  date=$(dec2bcd $1)
  i2c_write ${I2C_BUS} $I2C_MC_ADDRESS $I2C_CONF_DAY_ALARM1 $date
}

clear_startup_time()
{
  i2c_write ${I2C_BUS} $I2C_MC_ADDRESS $I2C_CONF_SECOND_ALARM1 0x00
  i2c_write ${I2C_BUS} $I2C_MC_ADDRESS $I2C_CONF_MINUTE_ALARM1 0x00
  i2c_write ${I2C_BUS} $I2C_MC_ADDRESS $I2C_CONF_HOUR_ALARM1 0x00
  i2c_write ${I2C_BUS} $I2C_MC_ADDRESS $I2C_CONF_DAY_ALARM1 0x00
}

get_shutdown_time()
{
  sec=$(bcd2dec $(i2c_read ${I2C_BUS} $I2C_MC_ADDRESS $I2C_CONF_SECOND_ALARM2))
  min=$(bcd2dec $(i2c_read ${I2C_BUS} $I2C_MC_ADDRESS $I2C_CONF_MINUTE_ALARM2))
  hour=$(bcd2dec $(i2c_read ${I2C_BUS} $I2C_MC_ADDRESS $I2C_CONF_HOUR_ALARM2))
  date=$(bcd2dec $(i2c_read ${I2C_BUS} $I2C_MC_ADDRESS $I2C_CONF_DAY_ALARM2))
  printf '%02d %02d:%02d:%02d\n' $date $hour $min $sec
}

set_shutdown_time()
{
  sec=$(dec2bcd $4)
  i2c_write ${I2C_BUS} $I2C_MC_ADDRESS $I2C_CONF_SECOND_ALARM2 $sec
  min=$(dec2bcd $3)
  i2c_write ${I2C_BUS} $I2C_MC_ADDRESS $I2C_CONF_MINUTE_ALARM2 $min
  hour=$(dec2bcd $2)
  i2c_write ${I2C_BUS} $I2C_MC_ADDRESS $I2C_CONF_HOUR_ALARM2 $hour
  date=$(dec2bcd $1)
  i2c_write ${I2C_BUS} $I2C_MC_ADDRESS $I2C_CONF_DAY_ALARM2 $date
}

get_startup_time_local()
{
  local raw=$(get_startup_time)
  if [ "$raw" == "00 00:00:00" ]; then
    echo "$raw"
  else
    local utc_ts=$(date -u --date="$(date -u +%Y-%m-)$raw" +%s)
    TZ=$LOCAL_TZ date -d @$utc_ts +'%d %H:%M:%S'
  fi
}

get_shutdown_time_local()
{
  local raw=$(get_shutdown_time)
  if [ "$raw" == "00 00:00:00" ]; then
    echo "$raw"
  else
    local utc_ts=$(date -u --date="$(date -u +%Y-%m-)$raw" +%s)
    TZ=$LOCAL_TZ date -d @$utc_ts +'%d %H:%M:%S'
  fi
}

clear_shutdown_time()
{
  i2c_write ${I2C_BUS} $I2C_MC_ADDRESS $I2C_CONF_SECOND_ALARM2 0x00
  i2c_write ${I2C_BUS} $I2C_MC_ADDRESS $I2C_CONF_MINUTE_ALARM2 0x00
  i2c_write ${I2C_BUS} $I2C_MC_ADDRESS $I2C_CONF_HOUR_ALARM2 0x00
  i2c_write ${I2C_BUS} $I2C_MC_ADDRESS $I2C_CONF_DAY_ALARM2 0x00
}

net_to_system()
{
  local net_ts=$(get_network_timestamp)
  if [[ "$net_ts" != "-1" ]]; then
    log '  Applying network time to system...'
    sudo date -u -s @$net_ts >/dev/null
    log '  Done :-)'
  else
    log '  Can not get legit network time.'
  fi
}

system_to_rtc()
{
  log '  Writing system time to RTC (as UTC)...'
  local sys_ts=$(get_sys_timestamp)
  local sec=$(date -u -d @$sys_ts +%S)
  local min=$(date -u -d @$sys_ts +%M)
  local hour=$(date -u -d @$sys_ts +%H)
  local day=$(date -u -d @$sys_ts +%u)
  local date=$(date -u -d @$sys_ts +%d)
  local month=$(date -u -d @$sys_ts +%m)
  local year=$(date -u -d @$sys_ts +%y)
  i2c_write ${I2C_BUS} $I2C_MC_ADDRESS 58 $(dec2bcd $sec)
  i2c_write ${I2C_BUS} $I2C_MC_ADDRESS 59 $(dec2bcd $min)
  i2c_write ${I2C_BUS} $I2C_MC_ADDRESS 60 $(dec2bcd $hour)
  i2c_write ${I2C_BUS} $I2C_MC_ADDRESS 61 $(dec2bcd $date)
  i2c_write ${I2C_BUS} $I2C_MC_ADDRESS 62 $(dec2bcd $day)
  i2c_write ${I2C_BUS} $I2C_MC_ADDRESS 63 $(dec2bcd $month)
  i2c_write ${I2C_BUS} $I2C_MC_ADDRESS 64 $(dec2bcd $year)
  TIME_UNKNOWN=2
  log '  Done :-)'
}

rtc_to_system()
{
  log '  Writing RTC time to system...'
  local rtc_ts=$(get_rtc_timestamp)
  sudo timedatectl set-ntp 0 >/dev/null
  sudo date -s @$rtc_ts >/dev/null
  TIME_UNKNOWN=0
  log '  Done :-)'
}

trim()
{
  local result=$(echo "$1" | sed -n '1h;1!H;${;g;s/^[ \t]*//g;s/[ \t]*$//g;p;}')
  echo $result
}

get_utc_offset_seconds()
{
  # Returns UTC offset in seconds for a given epoch in LOCAL_TZ
  # e.g. GMT=0, BST=3600
  local z=$(TZ=$LOCAL_TZ date -d @$1 +%z)
  local sign=${z:0:1}
  local hours=$((10#${z:1:2}))
  local mins=$((10#${z:3:2}))
  local secs=$(( hours * 3600 + mins * 60 ))
  if [ "$sign" = "-" ]; then
    secs=$((-secs))
  fi
  echo $secs
}

dst_correct()
{
  # Corrects an alarm epoch for DST drift relative to a schedule's BEGIN epoch.
  # When durations are added as fixed seconds, the local time-of-day drifts by
  # the DST offset difference. This function snaps the alarm back to the
  # intended local time.
  local begin_epoch=$1
  local alarm_epoch=$2
  local begin_off=$(get_utc_offset_seconds $begin_epoch)
  local alarm_off=$(get_utc_offset_seconds $alarm_epoch)
  echo $(( alarm_epoch + begin_off - alarm_off ))
}

enable_guaranteed_wake()
{
  # Backstop wake mechanism: instructs the firmware to wake the Pi at least
  # once every $1 hours (or days if $2='days') regardless of alarm state.
  # This is the primary recovery path for stuck alarms, drained RTC backup,
  # daemon crashes, SD corruption, and other field failures.
  #
  # Defensive: writes to register 49 (added in upstream Witty Pi 4 firmware,
  # all known revs >= 7). On older firmware the write is harmless EEPROM
  # storage with no effect; on supported firmware it provides the failsafe.
  local value=${1:-24}      # default: 24 hours
  local unit=${2:-hours}    # default: hours

  if [ "$unit" = "days" ]; then
    # bit 7 = 1 means days, bits 0-6 = count
    value=$(( (value & 0x7F) | 0x80 ))
  else
    # bit 7 = 0 means hours, bits 0-6 = count
    value=$(( value & 0x7F ))
  fi

  i2c_write ${I2C_BUS} $I2C_MC_ADDRESS $I2C_CONF_GUARANTEED_WAKE $value
  local readback=$(i2c_read ${I2C_BUS} $I2C_MC_ADDRESS $I2C_CONF_GUARANTEED_WAKE)
  if [ "$(($readback))" = "$value" ]; then
    log "Guaranteed wake enabled (reg49=$readback)."
  else
    log "Guaranteed wake write attempted (reg49=$readback, wanted $value). May be unsupported by older firmware."
  fi
}

enable_ignore_lv_shutdown()
{
  # Prevents a stale LV_SHUTDOWN=1 flag in EEPROM from blocking alarm1
  # startup wakes after a low-voltage event. Without this, a single
  # brownout can permanently disable scheduled wake until manual reset.
  i2c_write ${I2C_BUS} $I2C_MC_ADDRESS $I2C_CONF_IGNORE_LV_SHUTDOWN 1
  local readback=$(i2c_read ${I2C_BUS} $I2C_MC_ADDRESS $I2C_CONF_IGNORE_LV_SHUTDOWN)
  log "Ignore LV shutdown flag set (reg42=$readback)."
}

verify_alarm_in_future()
{
  # Reads back an alarm register block and confirms the encoded time is in
  # the future relative to current epoch. If the alarm is in the past or
  # zero, writes a fallback "now + 1 hour" alarm.
  # $1 = "startup" or "shutdown"
  local kind=$1
  local raw
  if [ "$kind" = "startup" ]; then
    raw=$(get_startup_time)
  else
    raw=$(get_shutdown_time)
  fi

  if [ "$raw" = "00 00:00:00" ]; then
    log "WARN: $kind alarm is zero after write - applying fallback (now + 1 hour)."
    apply_fallback_alarm "$kind"
    return
  fi

  # Reconstruct UTC epoch from the raw "DD HH:MM:SS" (alarm registers are
  # UTC since v4.24). Use current UTC month/year as context.
  local alarm_epoch=$(date -u --date="$(date -u +%Y-%m-)$raw" +%s 2>/dev/null)
  if [ -z "$alarm_epoch" ]; then
    log "WARN: could not parse $kind alarm '$raw' - applying fallback."
    apply_fallback_alarm "$kind"
    return
  fi

  local now=$(current_timestamp)
  # if alarm-day < today, it means the alarm is for next month; add a month
  local alarm_day=${raw:0:2}
  local today_day=$(date -u +%d)
  if [ $((10#$alarm_day)) -lt $((10#$today_day)) ]; then
    alarm_epoch=$((alarm_epoch + 86400 * 31))   # approx, fine for the in-future check
  fi

  if [ $alarm_epoch -le $((now + 30)) ]; then
    log "WARN: $kind alarm '$raw' is not safely in the future - applying fallback (now + 1 hour)."
    apply_fallback_alarm "$kind"
  fi
}

apply_fallback_alarm()
{
  # Writes a "now + 1 hour" alarm of the requested kind.
  # $1 = "startup" or "shutdown"
  local kind=$1
  local target=$(( $(current_timestamp) + 3600 ))
  local d=$(date -u -d "@$target" +"%d")
  local h=$(date -u -d "@$target" +"%H")
  local m=$(date -u -d "@$target" +"%M")
  local s=$(date -u -d "@$target" +"%S")
  if [ "$kind" = "startup" ]; then
    set_startup_time $d $h $m $s
  else
    set_shutdown_time $d $h $m $s
  fi
  log "Fallback $kind alarm set to: $(TZ=$LOCAL_TZ date -d @$target +'%Y-%m-%d %H:%M:%S %Z')"
}

current_timestamp()
{
  # prefer system time (kept accurate by NTP) over RTC
  local sys_ts=$(date +%s)
  local sys_year=$(date -u -d @$sys_ts +%Y)
  if [ "$sys_year" -gt 2020 ] 2>/dev/null; then
    echo $sys_ts
  else
    # system time not initialised yet, fall back to RTC
    local rtctimestamp=$(get_rtc_timestamp)
    if [ "$rtctimestamp" == "" ] ; then
      echo $sys_ts
    else
      echo $rtctimestamp
    fi
  fi
}

wittypi_home="`dirname \"$0\"`"
wittypi_home="`( cd \"$wittypi_home\" && pwd )`"
log2file()
{
  local datetime='[xxxx-xx-xx xx:xx:xx]'
  if [ $TIME_UNKNOWN -eq 0 ]; then
    datetime=$(TZ=$LOCAL_TZ date +'[%Y-%m-%d %H:%M:%S]')
  elif [ $TIME_UNKNOWN -eq 2 ]; then
    datetime=$(TZ=$LOCAL_TZ date +'<%Y-%m-%d %H:%M:%S>')
  fi
  local msg="$datetime $1"
  echo $msg >> $wittypi_home/wittyPi.log
}

log()
{
  if [ $# -gt 1 ] ; then
    echo $2 "$1"
  else
    echo "$1"
  fi
  log2file "$1"
}

i2c_read()
{
  local retry=0
  if [ $# -gt 3 ] ; then
    retry=$4
  fi
  local result=$(i2cget -y $1 $2 $3)
  if [[ $result =~ ^0x[0-9a-fA-F]{2}$ ]] ; then
    echo $result;
  else
    retry=$(( $retry + 1 ))
    if [ $retry -eq 4 ] ; then
      log "I2C read $1 $2 $3 failed (result=$result), and no more retry."
    else
      sleep 1
      log2file "I2C read $1 $2 $3 failed (result=$result), retrying $retry ..."
      i2c_read $1 $2 $3 $retry
    fi
  fi
}

i2c_write()
{
  local retry=0
  if [ $# -gt 4 ] ; then
    retry=$5
  fi
  i2cset -y $1 $2 $3 $4
  local result=$(i2c_read $1 $2 $3)
  if [ "$result" != $(dec2hex "$4") ] ; then
    retry=$(( $retry + 1 ))
    if [ $retry -eq 4 ] ; then
      log "I2C write $1 $2 $3 $4 failed (result=$result), and no more retry."
    else
      sleep 1
      log2file "I2C write $1 $2 $3 $4 failed (result=$result), retrying $retry ..."
      i2c_write $1 $2 $3 $4 $retry
    fi
  fi
}

get_temperature()
{
  local data=$(i2cget -y $I2C_BUS $I2C_MC_ADDRESS $I2C_LM75B_TEMPERATURE w)

  #if [[ $data =~ ^0x[0-9a-fA-F]{4}$ && $data != 0xffff ]]; then
  if [[ $data =~ ^0x[0-9a-fA-F]{4}$ ]]; then
    data=$(( ((($data&0xFF)<<8)|(($data&0xFF00)>>8))>>5 ))
    if [[ $data -ge 0x400 ]] ; then
      data=$(( ($data&0x3FF)-1024 ))
    fi
    local c=$(calc $data*0.125)
    echo -n "$c$(echo $'\xc2\xb0'C)"
    if hash awk 2>/dev/null; then
      local f=$(awk "BEGIN { print $c*1.8+32 }")
      echo " / $f$(echo $'\xc2\xb0'F)"
    else
      echo ''
    fi
  else
    sleep 0.1
    get_temperature
  fi
}

clear_alarm_flags()
{
  local ctrl2=0x0
  if [ -z "$1" ]; then
    ctrl2=$(i2c_read ${I2C_BUS} $I2C_MC_ADDRESS $I2C_RTC_CTRL2)
  else
    ctrl2=$1
  fi
  ctrl2=$(($ctrl2&0xBF))
  i2c_write ${I2C_BUS} $I2C_MC_ADDRESS $I2C_RTC_CTRL2 $ctrl2
  i2c_write ${I2C_BUS} $I2C_MC_ADDRESS $I2C_CONF_FLAG_ALARM1 0
  i2c_write ${I2C_BUS} $I2C_MC_ADDRESS $I2C_CONF_FLAG_ALARM2 0
}

schedule_script_interrupted()
{
  local startup_time=$(get_startup_time)
  local shutdown_time=$(get_shutdown_time)
  if [ "$startup_time" != '00 00:00:00' ] && [ "$shutdown_time" != '00 00:00:00' ] ; then
    local st_timestamp=$(_parse_alarm_to_epoch "$startup_time")
    local sd_timestamp=$(_parse_alarm_to_epoch "$shutdown_time")
    local cur_timestamp=$(date +%s)
    if [ -n "$st_timestamp" ] && [ -n "$sd_timestamp" ] \
       && [ $st_timestamp -gt $cur_timestamp ] && [ $sd_timestamp -lt $cur_timestamp ] ; then
      return 0
    fi
  fi
  return 1
}

_parse_alarm_to_epoch()
{
  # Convert a raw alarm "DD HH:MM:SS" (UTC) to an absolute UTC epoch,
  # handling the month-boundary case: if the alarm's day is less than
  # today's day, the alarm refers to NEXT month (e.g. today=2026-06-30,
  # alarm=01 → it means 2026-07-01, not 2026-06-01).
  # Returns empty string if parse fails.
  local raw="$1"
  local alarm_day=${raw:0:2}
  local today_day=$(date -u +%d)
  local ym
  if [ $((10#$alarm_day)) -lt $((10#$today_day)) ]; then
    # alarm is for next month
    ym=$(date -u -d "$(date -u +%Y-%m-01) +1 month" +%Y-%m-)
  else
    ym=$(date -u +%Y-%m-)
  fi
  date -u --date="${ym}${raw}" +%s 2>/dev/null
}

get_power_mode()
{
  local mode=$(i2c_read ${I2C_BUS} $I2C_MC_ADDRESS $I2C_POWER_MODE)
  echo $(($mode))
}

get_input_voltage()
{
  local i=$(i2c_read ${I2C_BUS} $I2C_MC_ADDRESS $I2C_VOLTAGE_IN_I)
  local d=$(i2c_read ${I2C_BUS} $I2C_MC_ADDRESS $I2C_VOLTAGE_IN_D)
  calc $(($i))+$(($d))/100
}

get_output_voltage()
{
  local i=$(i2c_read ${I2C_BUS} $I2C_MC_ADDRESS $I2C_VOLTAGE_OUT_I)
  local d=$(i2c_read ${I2C_BUS} $I2C_MC_ADDRESS $I2C_VOLTAGE_OUT_D)
  calc $(($i))+$(($d))/100
}

get_output_current()
{
  local i=$(i2c_read ${I2C_BUS} $I2C_MC_ADDRESS $I2C_CURRENT_OUT_I)
  local d=$(i2c_read ${I2C_BUS} $I2C_MC_ADDRESS $I2C_CURRENT_OUT_D)
  calc $(($i))+$(($d))/100
}

get_low_voltage_threshold()
{
  local lowVolt=$(i2c_read ${I2C_BUS} $I2C_MC_ADDRESS $I2C_CONF_LOW_VOLTAGE)
  if [ $(($lowVolt)) == 255 ]; then
    lowVolt='disabled'
  else
    lowVolt=$(calc $(($lowVolt))/10)
    lowVolt+='V'
  fi
  echo $lowVolt;
}

get_recovery_voltage_threshold()
{
  local recVolt=$(i2c_read ${I2C_BUS} $I2C_MC_ADDRESS $I2C_CONF_RECOVERY_VOLTAGE)
  if [ $(($recVolt)) == 255 ]; then
    recVolt='disabled'
  else
    recVolt=$(calc $(($recVolt))/10)
    recVolt+='V'
  fi
  echo $recVolt;
}

set_low_voltage_threshold()
{
  i2c_write ${I2C_BUS} $I2C_MC_ADDRESS $I2C_CONF_LOW_VOLTAGE $1
}

set_recovery_voltage_threshold()
{
  i2c_write ${I2C_BUS} $I2C_MC_ADDRESS $I2C_CONF_RECOVERY_VOLTAGE $1
}

clear_low_voltage_threshold()
{
  i2c_write ${I2C_BUS} $I2C_MC_ADDRESS $I2C_CONF_LOW_VOLTAGE 0xFF
}

clear_recovery_voltage_threshold()
{
  i2c_write ${I2C_BUS} $I2C_MC_ADDRESS $I2C_CONF_RECOVERY_VOLTAGE 0xFF
}

get_over_temperature_action()
{
  hex2dec $(i2c_read ${I2C_BUS} $I2C_MC_ADDRESS $I2C_CONF_OVER_TEMP_ACTION)
}

get_over_temperature_point()
{
  local t=$(hex2dec $(i2c_read ${I2C_BUS} $I2C_MC_ADDRESS $I2C_LM75B_TOS))
  if [ $(($t>127)) == '1' ]; then
    t=$(($t-256))
  fi
  printf "%d" $t
}

get_below_temperature_action()
{
  hex2dec $(i2c_read ${I2C_BUS} $I2C_MC_ADDRESS $I2C_CONF_BELOW_TEMP_ACTION)
}

get_below_temperature_point()
{
  local t=$(hex2dec $(i2c_read ${I2C_BUS} $I2C_MC_ADDRESS $I2C_LM75B_THYST))
  if [ $(($t>127)) == '1' ]; then
    t=$(($t-256))
  fi
  printf "%d" $t
}

over_temperature_action()
{
  if [ $# -eq 0 ]; then
    over_temperature_action $(get_over_temperature_action) $(get_over_temperature_point)
  else
    local action='None'
    if [ "$1" == '1' ]; then
      action='Shutdown'
    elif [ "$1" == '2' ]; then
      action='Startup'
    fi
    if [ "$action" != 'None' ]; then
      echo -n "T>$2$(echo $'\xc2\xb0'C) $(echo -e '\u2794') $action"
    fi
  fi
}

below_temperature_action()
{
  if [ $# -eq 0 ]; then
    below_temperature_action $(get_below_temperature_action) $(get_below_temperature_point)
  else
    local action='None'
    if [ "$1" == '1' ]; then
      action='Shutdown'
    elif [ "$1" == '2' ]; then
      action='Startup'
    fi
    if [ "$action" != 'None' ]; then
      echo -n "T<$2$(echo $'\xc2\xb0'C) $(echo -e '\u2794') $action"
    fi
  fi
}

set_over_temperature_action()
{
  i2c_write ${I2C_BUS} $I2C_MC_ADDRESS $I2C_CONF_OVER_TEMP_ACTION $1
  local t=$2
  if [ $(($2<0)) == '1' ]; then
    t=$(($2+256))
  fi
  i2c_write ${I2C_BUS} $I2C_MC_ADDRESS $I2C_LM75B_TOS $t
  i2c_write ${I2C_BUS} $I2C_MC_ADDRESS $I2C_CONF_OVER_TEMP_POINT $t
}

set_below_temperature_action()
{
  i2c_write ${I2C_BUS} $I2C_MC_ADDRESS $I2C_CONF_BELOW_TEMP_ACTION $1
  local t=$2
  if [ $(($2<0)) == '1' ]; then
    t=$(($2+256))
  fi
  i2c_write ${I2C_BUS} $I2C_MC_ADDRESS $I2C_LM75B_THYST $t
  i2c_write ${I2C_BUS} $I2C_MC_ADDRESS $I2C_CONF_BELOW_TEMP_POINT $t
}

clear_over_temperature_action()
{
  i2c_write ${I2C_BUS} $I2C_MC_ADDRESS $I2C_CONF_OVER_TEMP_ACTION 0x00
}

clear_below_temperature_action()
{
  i2c_write ${I2C_BUS} $I2C_MC_ADDRESS $I2C_CONF_BELOW_TEMP_ACTION 0x00
}

check_sys_and_rtc_time()
{
  local rtc_ts=$(get_rtc_timestamp)
  local sys_ts=$(get_sys_timestamp)
  local delta=$((rtc_ts-sys_ts))
  if [ "${delta#-}" -gt 10 ]; then
    local rtc_t=$(TZ=$LOCAL_TZ date +'%Y-%m-%d %H:%M:%S %Z' -d @$rtc_ts)
    local sys_t=$(TZ=$LOCAL_TZ date +'%Y-%m-%d %H:%M:%S %Z' -d @$sys_ts)
    echo "[Warning] System and RTC time seems not synchronized, difference is ${delta#-}s."
    echo "System time is \"$sys_t\", while RTC time is \"$rtc_t\"."
    echo 'Please synchronize the time first.'
  fi
}
