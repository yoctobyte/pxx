#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# MicroPython's networking libraries on an emulated ESP32, against a host stub:
# ntptime, umqtt.simple and umqtt.robust, compiled from micropython-lib's own
# source (tools/install_lib_candidates.sh micropython-net), talking to
# tools/esp_qemu_net/mpy_net_stub.py over QEMU's open_eth + slirp.
#
#   tools/esp_qemu_mpy_net.sh nilpy-hw-s3|nilpy-hw-c3
#
# The -hw- projects, not nilpy-s3/-c3: ntptime.settime imports machine, and
# mimic_machine links the ESP I2C/RMT drivers, which only the -hw- projects
# REQUIRE (the plain ones fail to link on i2c_master_transmit_receive).
#
# ONE EDIT TO ONE LIBRARY, and it is the environment's, not the library's:
# ntptime sends to port 123, which an unprivileged user cannot bind on the host
# (ip_unprivileged_port_start is 1024 here, and user namespaces are refused).
# The staged copy of ntptime.py has that one literal replaced by the stub's
# kernel-picked port; every other line is upstream's. umqtt is unchanged.
#
# Rows, each printed as MPYNET-ROW <name> OK|FAIL:
#   desktop   the same client built for the host runs against the same stub
#   chip      the chip's transcript equals the desktop's (the stub's ports and
#             10.0.2.2 are the only substitutions)
#   ntp       ntptime.time() on the chip equals CPython running the same staged
#             ntptime.py against the same stub
#   broker    the stub's log for the chip run shows both clients' sessions
#   census:<lib>  free heap across 1000 dropped iterations of ntptime.time(),
#             an umqtt.simple session and an umqtt.robust session (each after
#             20 warm-ups) costs under BOUND bytes per iteration (default 16)
#   control   keeping 200 umqtt.simple clients reads ABOVE the bound, or the
#             heap reading could not have seen a leak
#   sessions  the stub saw every census session connect
# The census is tools/esp_qemu_net/mpy_net_census.npy, appended to the chip's
# program only (the desktop has no free_heap). QEMU runs this far slower than
# real time, so the default timeout is generous; the emulated chip's own ms figures
# are printed beside each census row.
# Last line: MPYNET-QEMU-COMPLETE. Grep for that; the wrapper's status is not
# the verdict. Built with the PINNED compiler unless PXX says otherwise.
#
# MEASURED 2026-09-25, HEAD compiler 8bfa6543bc28: nilpy-hw-s3 every row OK.
# nilpy-hw-c3 STALLS partway through the census (after 250..1000 umqtt
# sessions; on pin v438 after 421). It is not a leak and not a handle running
# out: with MPYNET_GDB_PORT set, stall_probe.gdb found all four openeth rx
# descriptors full (e=0), INT_SOURCE = RXB|BUSY with RXB unmasked, and the
# emac_rx task still blocked in ulTaskNotifyTake -- the emulated NIC's rx
# interrupt is pending and never delivered, so the chip waits forever for
# frames it already holds. Sockets 0..1 of 10, TIME_WAIT pcbs at lwIP's cap
# (15+1). The same shape stops esp_qemu_urequests.sh on the C3. The S3 (a
# different interrupt controller model) has never shown it.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EX="${1:?usage: esp_qemu_mpy_net.sh nilpy-hw-s3|nilpy-hw-c3}"
case "$EX" in *-c3) CHIP=esp32c3 ;; *-s3) CHIP=esp32s3 ;; *) echo "mpynet: $EX is not -c3/-s3" >&2; exit 2 ;; esac
SRC="$REPO_ROOT/examples/esp32/$EX"
[ -f "$SRC/main/main.npy" ] || { echo "mpynet: $EX has no main/main.npy" >&2; exit 2; }
LIB="$REPO_ROOT/library_candidates/micropython-net/micropython-lib/micropython"
if [ ! -f "$LIB/umqtt.simple/umqtt/simple.py" ]; then
  echo "MPYNET-ROW all SKIP (no micropython-net: tools/install_lib_candidates.sh micropython-net)"
  echo "MPYNET-QEMU-COMPLETE"; exit 0
fi
PXX="${PXX:-$("$REPO_ROOT/tools/pxx_stable.sh")}"
# MPYNET_CENSUS=stall swaps the census for mpy_net_stall.npy (the C3 umqtt
# stall, reduced); MPYNET_GDB_PORT=<n> starts QEMU with a gdbserver on it, so a
# stalled chip can be read with the target's gdb (the ELF is kept with
# MPYNET_KEEP=1, under the stage's build/).
TIMEOUT="${MPYNET_TIMEOUT:-1800}"   # the S3 census measured 3.5 min wall, 2026-09-25
BOUND="${MPYNET_BOUND:-16}"
ESP_IDF_DIR="${ESP_IDF_DIR:-$HOME/esp/esp-idf}"

W="$(mktemp -d "${TMPDIR:-/tmp}/esp-qemu-mpynet.XXXXXX")"
QPID=""; SPID=""
cleanup() {
  [ -n "$QPID" ] && kill "$QPID" 2>/dev/null
  [ -n "$SPID" ] && kill "$SPID" 2>/dev/null
  if [ -n "${MPYNET_KEEP:-}" ]; then echo "mpynet: stage kept at $W" >&2; else rm -rf "$W"; fi
}
trap cleanup EXIT
fail_out() { echo "MPYNET-ROW $1 FAIL"; shift; printf '  | %s\n' "$@"; echo "MPYNET-QEMU-COMPLETE"; exit 1; }

start_stub() {   # $1 = log file; sets SPID, MQTT_PORT, NTP_PORT
  python3 "$REPO_ROOT/tools/esp_qemu_net/mpy_net_stub.py" >"$1" 2>&1 &
  SPID=$!
  for i in $(seq 40); do grep -q '^ready ' "$1" && break; sleep 0.25; done
  MQTT_PORT="$(sed -n 's/^ready \([0-9]*\) \([0-9]*\)$/\1/p' "$1" | head -n 1)"
  NTP_PORT="$(sed -n 's/^ready \([0-9]*\) \([0-9]*\)$/\2/p' "$1" | head -n 1)"
  [ -n "$NTP_PORT" ] || fail_out stub "the host stub never came up" "$(cat "$1")"
}
stop_stub() { [ -n "$SPID" ] && kill "$SPID" 2>/dev/null; wait "$SPID" 2>/dev/null || true; SPID=""; }
stage_ntp() {    # the port-123 edit, and nothing else
  mkdir -p "$W/ntp"
  sed "s/getaddrinfo(host, 123)/getaddrinfo(host, $NTP_PORT)/" "$LIB/net/ntptime/ntptime.py" > "$W/ntp/ntptime.py"
  grep -q "getaddrinfo(host, $NTP_PORT)" "$W/ntp/ntptime.py" \
    || fail_out stage "ntptime.py no longer has the getaddrinfo(host, 123) line this edits"
}
client() {       # $1 host, $2 preamble file or empty, $3 out, $4 "census" to append it
  { if [ -n "$2" ]; then cat "$2"; fi
    sed -e "s/@HOST@/$1/g" -e "s/@MQTT_PORT@/$MQTT_PORT/g" -e '/^@PREAMBLE@$/d' \
      "$REPO_ROOT/tools/esp_qemu_net/mpy_net_client.npy"
    if [ "${4:-}" = census ]; then
      printf '\n\n'
      sed -e "s/@HOST@/$1/g" -e "s/@MQTT_PORT@/$MQTT_PORT/g" "$REPO_ROOT/tools/esp_qemu_net/mpy_net_${MPYNET_CENSUS:-census}.npy"
    fi; } > "$3"
}
LIBFU="-Fu$W/ntp -Fu$LIB/umqtt.simple -Fu$LIB/umqtt.robust"

# -- the desktop row, and the CPython oracle for ntptime
start_stub "$W/stub.desktop.log"
stage_ntp
client 127.0.0.1 "" "$W/desktop.npy"
# shellcheck disable=SC2086
"$PXX" $LIBFU "$W/desktop.npy" "$W/desktop" >"$W/desktop.build" 2>&1 \
  || fail_out desktop "$(grep -m3 error "$W/desktop.build" || true)"
timeout 30 "$W/desktop" >"$W/desktop.txt" 2>&1 || true
( cd "$W/ntp" && python3 -c "import ntptime; ntptime.host = '127.0.0.1'; print('ntptime', ntptime.time())" ) >"$W/oracle.txt" 2>&1 || true
stop_stub
if grep -q '^MPYNET-COMPLETE$' "$W/desktop.txt"; then echo "MPYNET-ROW desktop OK"
else fail_out desktop "$(tail -5 "$W/desktop.txt")"; fi

# -- the chip: a fresh stub, so its log is the chip's alone
start_stub "$W/stub.chip.log"
stage_ntp
mkdir -p "$W/$EX"
tar -C "$SRC" -h --exclude=build --exclude=sdkconfig --exclude='*.o' --exclude='*.a' -cf - . \
  | tar -C "$W/$EX" -xf -
cd "$W/$EX"
mkdir -p components
cp -r "$REPO_ROOT/tools/esp_qemu_net/qemueth" components/
cp "$REPO_ROOT/tools/esp_qemu_net/qemueth.pas" main/
# QEMU-only settings; tools/esp_qemu_urequests.sh says why each is there.
printf '\nCONFIG_ETH_USE_OPENETH=y\nCONFIG_LWIP_TCP_MSL=500\nCONFIG_ESP_INT_WDT=n\nCONFIG_ESP_TASK_WDT_EN=n\n' >> sdkconfig.defaults
sed -i -e 's/REQUIRES \([^)]*\))/REQUIRES \1 qemueth)/' main/CMakeLists.txt
printf 'import %sqemueth.pas%s as qemueth\nrc = qemueth.up(30000)\nprint("MPYNET-ETH rc=" + str(rc))\n' "'" "'" > "$W/preamble.npy"
client 10.0.2.2 "$W/preamble.npy" main/main.npy census
sed -i -e "s|^REPO_ROOT=.*|REPO_ROOT=\"$REPO_ROOT\"|" build.sh

. "$ESP_IDF_DIR/export.sh" >/dev/null 2>&1
if ! PXX="$PXX" PXX_EXTRA_FLAGS="-Fu$W/$EX/main $LIBFU ${PXX_EXTRA_FLAGS:-}" bash build.sh >"$W/build.log" 2>&1; then
  fail_out build "$(grep -a -m3 'error' "$W/build.log" || true)" "$(tail -5 "$W/build.log")"
fi
case "$CHIP" in
  esp32s3) QEMU="$(ls "$HOME"/.espressif/tools/qemu-xtensa/*/qemu/bin/qemu-system-xtensa | head -1)" ;;
  *)       QEMU="$(ls "$HOME"/.espressif/tools/qemu-riscv32/*/qemu/bin/qemu-system-riscv32 | head -1)" ;;
esac
( cd build && python -m esptool --chip "$CHIP" merge-bin -o "$W/flash.bin" @flash_args --fill-flash-size 4MB >/dev/null 2>&1 )
"$QEMU" -M "$CHIP" -drive file="$W/flash.bin",if=mtd,format=raw -nic user,model=open_eth \
  -nographic -serial mon:stdio -monitor none ${MPYNET_GDB_PORT:+-gdb tcp::$MPYNET_GDB_PORT} >"$W/serial.log" 2>&1 &
QPID=$!
t=0
lastsz=-1; still=0
while [ $t -lt "$TIMEOUT" ] && ! grep -qa 'MPYNET-CENSUS-DONE\|Rebooting\|Unhandled exception' "$W/serial.log"; do
  sleep 1; t=$((t + 1))
  # With a gdbserver, a chip SILENT for MPYNET_STALL_S seconds (default 120)
  # after the census began is read once with stall_probe.gdb, and the wait ends.
  if [ -n "${MPYNET_GDB_PORT:-}" ] && grep -qa '^MPYNET-STALL n=\|^MPYNET-HEAP' "$W/serial.log"; then
    sz=$(stat -c %s "$W/serial.log")
    if [ "$sz" = "$lastsz" ]; then still=$((still + 1)); else still=0; lastsz=$sz; fi
    if [ "$still" -ge "${MPYNET_STALL_S:-120}" ]; then
      case "$CHIP" in esp32s3) GDB=xtensa-esp32s3-elf-gdb ;; *) GDB=riscv32-esp-elf-gdb ;; esac
      GDBBIN="$(ls "$HOME"/.espressif/tools/*-gdb/*/*/bin/$GDB | head -1)"
      ELF="$(ls build/*.elf | head -1)"
      echo "MPYNET-STALLED after ${still}s silent at $(grep -a '^MPYNET-STALL n=\|^MPYNET-HEAP' "$W/serial.log" | tail -1 | tr -d '\r')"
      STEPS=(); while IFS= read -r l; do STEPS+=(-ex "$l"); done < "$REPO_ROOT/tools/esp_qemu_net/stall_probe.steps"
      timeout 120 "$GDBBIN" -q -batch -ex "target remote :$MPYNET_GDB_PORT" \
        -x "$REPO_ROOT/tools/esp_qemu_net/stall_probe.gdb" "${STEPS[@]}" "$ELF" 2>&1 | grep -a 'STALL-GDB\|^\$\|^#' | head -120
      break
    fi
  fi
done
kill "$QPID" 2>/dev/null || true; QPID=""
stop_stub
tr -d '\r' < "$W/serial.log" > "$W/serial.txt"
grep -qa '^MPYNET-COMPLETE' "$W/serial.txt" \
  || fail_out chip "no MPYNET-COMPLETE after ${t}s" "$(grep -a 'MPYNET-\|Unhandled\|Rebooting\|Guru' "$W/serial.txt" | head -5)" "$(tail -5 "$W/serial.txt")"
echo "MPYNET $EX $CHIP $(grep -a '^MPYNET-ETH' "$W/serial.txt")"
sed -n '/^MPYNET-BEGIN$/,/^MPYNET-COMPLETE$/p' "$W/serial.txt" > "$W/chip.txt"
sed -n '/^MPYNET-BEGIN$/,/^MPYNET-COMPLETE$/p' "$W/desktop.txt" > "$W/desk.txt"
if diff "$W/desk.txt" "$W/chip.txt" >"$W/chip.diff"; then echo "MPYNET-ROW chip OK ($(wc -l < "$W/chip.txt") lines = desktop)"
else echo "MPYNET-ROW chip FAIL"; sed 's/^/  | /' "$W/chip.diff" | head -20; fi
if [ "$(grep -a '^ntptime ' "$W/chip.txt" || true)" = "$(cat "$W/oracle.txt")" ]; then echo "MPYNET-ROW ntp OK ($(cat "$W/oracle.txt") = CPython)"
else echo "MPYNET-ROW ntp FAIL (chip: $(grep -a '^ntptime ' "$W/chip.txt" || echo none); CPython: $(cat "$W/oracle.txt"))"; fi
# The transcript's sessions are the ones before the census's first connect.
sed '/^CONNECT client cen-/,$d' "$W/stub.chip.log" > "$W/stub.transcript.log"
if [ "$(grep -c '^CONNECT client pxx-' "$W/stub.transcript.log")" = 2 ] && [ "$(grep -c '^DISCONNECT' "$W/stub.transcript.log")" = 2 ]; then
  echo "MPYNET-ROW broker OK (two sessions, $(grep -c '^PUBLISH' "$W/stub.transcript.log") publishes)"
else echo "MPYNET-ROW broker FAIL"; sed 's/^/  | /' "$W/stub.transcript.log"; fi

if [ "${MPYNET_CENSUS:-census}" = stall ]; then
  # The stall loop: its checkpoints ARE the result (fd flat = no socket kept;
  # free heap flat = nothing kept), and the stub counts what reached it.
  grep -a '^MPYNET-STALL n=' "$W/serial.txt" | awk 'NR<=2 || NR%20==0' | sed 's/^/  | /'
  grep -a '^MPYNET-STALL n=' "$W/serial.txt" | tail -1 | sed 's/^/  | last: /'
  fds="$(grep -a '^MPYNET-STALL n=' "$W/serial.txt" | sed -n 's/.* fd=\([0-9-]*\).*/\1/p' | sort -un | tr '\n' ' ')"
  ns="$(grep -c '^CONNECT client cen-simple' "$W/stub.chip.log" || true)"
  if grep -qa '^MPYNET-STALL-DONE' "$W/serial.txt" && [ "$ns" = 3000 ]; then
    echo "MPYNET-ROW stall OK (3000 sessions reached the stub; fds seen: $fds)"
  else echo "MPYNET-ROW stall FAIL (stub saw simple=$ns; fds seen: $fds)"; fi
  echo "MPYNET-QEMU-COMPLETE"; exit 0
fi
grep -qa '^MPYNET-CENSUS-DONE' "$W/serial.txt" \
  || fail_out census "no MPYNET-CENSUS-DONE after ${t}s" "$(grep -a 'MPYNET-HEAP\|MPYNET-CENSUS\|Rebooting\|Guru' "$W/serial.txt" | tail -5)"
bpi() { sed -n 's/.* bpi=\(-\{0,1\}[0-9]*\).*/\1/p'; }
for lib in ntptime umqtt.simple umqtt.robust; do
  row="$(grep -a "^MPYNET-CENSUS $lib " "$W/serial.txt" || true)"; b="$(printf '%s' "$row" | bpi)"
  if [ -n "$b" ] && [ "$b" -lt "$BOUND" ]; then echo "MPYNET-ROW census:$lib OK (${row#MPYNET-CENSUS }, bound $BOUND)"
  else echo "MPYNET-ROW census:$lib FAIL (${row#MPYNET-CENSUS }, bound $BOUND)"; fi
done
row="$(grep -a '^MPYNET-CENSUS control ' "$W/serial.txt" || true)"; b="$(printf '%s' "$row" | bpi)"
if [ -n "$b" ] && [ "$b" -gt "$BOUND" ]; then echo "MPYNET-ROW control OK (${row#MPYNET-CENSUS }, must exceed $BOUND)"
else echo "MPYNET-ROW control FAIL (${row#MPYNET-CENSUS }: keeping clients did not read above the bound)"; fi
# 20 warm-ups + 1000 per library, plus the control's 200 simple sessions.
ns="$(grep -c '^CONNECT client cen-simple' "$W/stub.chip.log" || true)"; nr="$(grep -c '^CONNECT client cen-robust' "$W/stub.chip.log" || true)"
nq="$(grep -c '^NTP query answered' "$W/stub.chip.log" || true)"
if [ "$ns" = 1220 ] && [ "$nr" = 1020 ] && [ "$nq" -ge 1021 ]; then echo "MPYNET-ROW sessions OK (stub saw simple=$ns robust=$nr ntp=$nq)"
else echo "MPYNET-ROW sessions FAIL (stub saw simple=$ns robust=$nr ntp=$nq; want 1220, 1020, >=1021)"; fi
echo "MPYNET-QEMU-COMPLETE"
