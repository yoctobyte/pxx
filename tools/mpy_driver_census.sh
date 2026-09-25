#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# MicroPython driver census: compile widely used MicroPython device drivers,
# UNCHANGED, as NilPy for the ESP32-S3, and report the first wall of each.
#
#   tools/install_lib_candidates.sh micropython-drivers   # once: the drivers
#   tools/mpy_driver_census.sh                            # the table
#   PXX=compiler/pascal26 tools/mpy_driver_census.sh      # against HEAD
#
# Each row compiles test/mpy_drivers/m_<driver>.npy, a MicroPython-style main
# that imports the driver from its upstream checkout (via -Fu), against our
# machine/framebuf/time surface. "compiles" means the S3 object was produced;
# nothing here runs on a board. The first error is the FIRST wall only: what
# is behind it is unknown until it moves (a compile stops at one error).
#
# The table names the compiler (sha256) and the driver population, so a row
# can be re-derived. A row whose driver directory is absent reads
# "not installed", never a wall. Ends with MPY-DRIVER-CENSUS-COMPLETE.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
PXX="${PXX:-$("$ROOT/tools/pxx_stable.sh")}"
# The set: `drivers` (the default) or `net`, MicroPython's networking
# libraries. Same loop, same flags; each set has its own fetched tree, its own
# PROVENANCE.md and its own mains (test/mpy_<set>/m_<name>.npy).
SET="${1:-drivers}"
case "$SET" in
  drivers|net) ;;
  *) echo "mpy_driver_census: unknown set '$SET' (drivers|net)" >&2; exit 2 ;;
esac
C="$ROOT/library_candidates/micropython-$SET"
MAINS="test/mpy_$SET"
if [ ! -f "$C/PROVENANCE.md" ]; then
  echo "mpy_driver_census: nothing under $C -- run tools/install_lib_candidates.sh micropython-$SET" >&2
  exit 2
fi
OUT="$(mktemp -d)"

# driver | directory the main's import resolves in (':'-separated when the
# driver imports a sibling from another directory, as ds18x20 imports onewire)
if [ "$SET" = drivers ]; then
ROWS="ssd1306|micropython-lib/micropython/drivers/display/ssd1306
bme280|BME280
ads1x15|ads1x15
mpu6050|micropython-mpu9x50
ds3231|micropython-samples/DS3231
max7219|micropython-max7219
st7789|st7789py_mpy/lib
sdcard|micropython-lib/micropython/drivers/storage/sdcard
dht|micropython-lib/micropython/drivers/sensor/dht
ds18x20|micropython-lib/micropython/drivers/sensor/ds18x20:micropython-lib/micropython/drivers/bus/onewire
neopixel|micropython-lib/micropython/drivers/led/neopixel
sh1106|SH1106
ina219|pyb_ina219:micropython-lib-logging/python-stdlib/logging
hcsr04|micropython-hcsr04
tm1637|micropython-tm1637
bh1750|bh1750fvi"
else
ROWS="umqtt_simple|micropython-lib/micropython/umqtt.simple
umqtt_robust|micropython-lib/micropython/umqtt.robust:micropython-lib/micropython/umqtt.simple
ntptime|micropython-lib/micropython/net/ntptime
uaiohttpclient|micropython-lib/micropython/uaiohttpclient
mqtt_as|micropython-mqtt
microdot|microdot/src
asyncio_streams|."
fi

echo "compiler: $PXX ($(sha256sum "$(readlink -f "$PXX")" | cut -c1-12))"
echo "tree: $(git -C "$ROOT" rev-parse --short=10 HEAD)"
echo "$SET: $(grep '^| [a-z0-9_]* |' "$C/PROVENANCE.md" | grep -vc '^| driver |') rows in $C/PROVENANCE.md"
echo
echo "| driver | compiles | first wall |"
echo "| --- | --- | --- |"
ok=0; n=0; absent=0
while IFS='|' read -r drv dir; do
  n=$((n + 1))
  log="$OUT/$drv.log"
  fu=(); miss=""; IFS=':' read -ra dirs <<< "$dir"
  for d in "${dirs[@]}"; do
    fu+=("-Fu$C/$d")
    [ -d "$C/$d" ] || miss="${miss:+$miss, }$d"
  done
  # A driver that is not on disk is not a compile wall: the compiler would
  # report "no unit named <driver>", which reads exactly like one. A plain
  # install_lib_candidates.sh skips a directory that exists, so rows added to
  # the recipe after the first fetch are absent until FORCE=1.
  if [ -n "$miss" ]; then
    absent=$((absent + 1))
    echo "| $drv | not installed | $miss missing: FORCE=1 tools/install_lib_candidates.sh micropython-$SET |"
    continue
  fi
  if "$PXX" --target=xtensa --xtensa-abi=windowed --xtensa-long-calls --platform=esp --no-signals \
       -Fu"$ROOT/lib/rtl" -Fu"$ROOT/lib/rtl/platform/esp" "${fu[@]}" \
       "$MAINS/m_$drv.npy" "$OUT/$drv.o" > "$log" 2>&1 && [ -s "$OUT/$drv.o" ]; then
    ok=$((ok + 1))
    bss="$(grep -o 'bss=[0-9]*B' "$log" | tail -1)"
    echo "| $drv | yes | -- ($bss) |"
  else
    wall="$(grep -m1 -E 'error|Error|fatal' "$log" | cut -c1-160)"
    near="$(grep -m1 'near:' "$log" | sed 's/^ *//' | cut -c1-80)"
    echo "| $drv | no | ${wall:-rc!=0, no error line} ${near:+($near)} |"
  fi
done <<< "$ROWS"
echo
echo "compiled: $ok of $n"
[ "$absent" -gt 0 ] && echo "not installed: $absent of $n (not measured; see the rows)"
echo "logs: $OUT"
echo MPY-DRIVER-CENSUS-COMPLETE
