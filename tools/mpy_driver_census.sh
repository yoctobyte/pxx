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
# can be re-derived. Ends with MPY-DRIVER-CENSUS-COMPLETE.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
PXX="${PXX:-$("$ROOT/tools/pxx_stable.sh")}"
C="$ROOT/library_candidates/micropython-drivers"
if [ ! -f "$C/PROVENANCE.md" ]; then
  echo "mpy_driver_census: no drivers under $C -- run tools/install_lib_candidates.sh micropython-drivers" >&2
  exit 2
fi
OUT="$(mktemp -d)"

# driver | directory the main's import resolves in (':'-separated when the
# driver imports a sibling from another directory, as ds18x20 imports onewire)
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
ina219|pyb_ina219:micropython-lib/python-stdlib/logging
hcsr04|micropython-hcsr04
tm1637|micropython-tm1637
bh1750|bh1750fvi"

echo "compiler: $PXX ($(sha256sum "$(readlink -f "$PXX")" | cut -c1-12))"
echo "tree: $(git -C "$ROOT" rev-parse --short=10 HEAD)"
echo "drivers: $(grep '^| [a-z0-9]* |' "$C/PROVENANCE.md" | grep -vc '^| driver |') rows in $C/PROVENANCE.md"
echo
echo "| driver | compiles | first wall |"
echo "| --- | --- | --- |"
ok=0; n=0
while IFS='|' read -r drv dir; do
  n=$((n + 1))
  log="$OUT/$drv.log"
  fu=(); IFS=':' read -ra dirs <<< "$dir"
  for d in "${dirs[@]}"; do fu+=("-Fu$C/$d"); done
  if "$PXX" --target=xtensa --xtensa-abi=windowed --xtensa-long-calls --platform=esp --no-signals \
       -Fu"$ROOT/lib/rtl" -Fu"$ROOT/lib/rtl/platform/esp" "${fu[@]}" \
       "test/mpy_drivers/m_$drv.npy" "$OUT/$drv.o" > "$log" 2>&1 && [ -s "$OUT/$drv.o" ]; then
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
echo "logs: $OUT"
echo MPY-DRIVER-CENSUS-COMPLETE
