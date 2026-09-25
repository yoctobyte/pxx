#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# urequests (lib/rtl/mimic_urequests.py) on an emulated ESP32 -- the QEMU row
# that stands in for the silicon one (S3 as a station, a server on the
# desktop) until a board is available.
#
#   tools/esp_qemu_urequests.sh nilpy-s3|nilpy-c3
#
# The PLAIN NilPy project is staged out of tree (the checkout stays clean), and
# three things are added to it: tools/esp_qemu_net/qemueth (QEMU's open_eth MAC
# + slirp DHCP; QEMU-only, never in a silicon image), CONFIG_ETH_USE_OPENETH,
# and tools/esp_qemu_net/urequests_client.npy as main.npy. The host runs
# test/lib_mimic_urllib_request_server.pas on a kernel-picked port; the chip
# reaches it as 10.0.2.2 through `-nic user,model=open_eth`.
#
# Rows, each printed as UREQ-ROW <name> OK|FAIL:
#   transcript  the chip's output for test/lib_mimic_urequests.npy's calls
#               (get, 404, json(), post json/data+headers, put, patch, delete,
#               a 3xx not followed, head) equals CPython `requests` run on
#               the host against the SAME server (test/urequests_oracle/).
#               SKIP when python3 has no `requests`.
#   census      free heap over 1000 requests with dropped responses costs
#               under BOUND bytes per request (default 16)...
#   control     ...and keeping 200 responses costs over it, so the reading
#               can see a leak at all.
# Last line: UREQ-QEMU-COMPLETE. Grep for that; the wrapper's status is not
# the verdict. Built with the PINNED compiler unless PXX says otherwise.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EX="${1:?usage: esp_qemu_urequests.sh nilpy-s3|nilpy-c3}"
case "$EX" in *-c3) CHIP=esp32c3 ;; *-s3) CHIP=esp32s3 ;; *) echo "ureq: $EX is not -c3/-s3" >&2; exit 2 ;; esac
SRC="$REPO_ROOT/examples/esp32/$EX"
[ -f "$SRC/main/main.npy" ] || { echo "ureq: $EX has no main/main.npy" >&2; exit 2; }
PXX="${PXX:-$("$REPO_ROOT/tools/pxx_stable.sh")}"
TIMEOUT="${UREQ_TIMEOUT:-600}"
BOUND="${UREQ_BOUND:-16}"
ESP_IDF_DIR="${ESP_IDF_DIR:-$HOME/esp/esp-idf}"

W="$(mktemp -d "${TMPDIR:-/tmp}/esp-qemu-ureq.XXXXXX")"
QPID=""; SPID=""
cleanup() {
  [ -n "$QPID" ] && kill "$QPID" 2>/dev/null
  [ -n "$SPID" ] && kill "$SPID" 2>/dev/null
  if [ -n "${UREQ_KEEP:-}" ]; then echo "ureq: stage kept at $W" >&2; else rm -rf "$W"; fi
}
trap cleanup EXIT
fail_out() { echo "UREQ-ROW $1 FAIL"; shift; printf '  | %s\n' "$@"; echo "UREQ-QEMU-COMPLETE"; exit 1; }

# -- the host server, on a port the kernel picks
"$PXX" "$REPO_ROOT/test/lib_mimic_urllib_request_server.pas" "$W/srv" >/dev/null \
  || fail_out build "the host test server did not compile"
"$W/srv" 0 >"$W/srv.log" 2>&1 &
SPID=$!
for i in $(seq 40); do grep -q '^ready ' "$W/srv.log" && break; sleep 0.25; done
PORT="$(sed -n 's/^ready //p' "$W/srv.log" | head -n 1)"
[ -n "$PORT" ] || fail_out server "the host test server never came up"

# -- the oracle: the same calls under CPython requests, against the same server
ORACLE=1
if python3 -c 'import requests' 2>/dev/null; then
  PYTHONPATH="$REPO_ROOT/test/urequests_oracle" python3 "$REPO_ROOT/test/lib_mimic_urequests.npy" "$PORT" \
    >"$W/oracle.txt" 2>&1 || fail_out transcript "CPython oracle failed" "$(tail -3 "$W/oracle.txt")"
else
  ORACLE=0
fi

# -- stage the plain project
mkdir -p "$W/$EX"
tar -C "$SRC" -h --exclude=build --exclude=sdkconfig --exclude='*.o' --exclude='*.a' -cf - . \
  | tar -C "$W/$EX" -xf -
cd "$W/$EX"
mkdir -p components
cp -r "$REPO_ROOT/tools/esp_qemu_net/qemueth" components/
cp "$REPO_ROOT/tools/esp_qemu_net/qemueth.pas" main/
# QEMU-ONLY settings, and why each is here. MSL 500 ms: the host test server
# answers keep-alive, so the CHIP closes first and every connection sits in
# TIME_WAIT for 2*MSL (IDF default 120 s) holding its PCB -- measured ~268 B per
# request, which exhausts the S3's heap near request 500 and would read as a
# leak. The census wants our leaks, not lwIP's TIME_WAIT. (It does not sleep to
# settle: a time.sleep_ms after the 1000-request loop never returned on the
# emulated C3, 2026-09-25, while the same call before the loop did.) Watchdogs off: under a loaded host the
# emulated C3 tripped the INTERRUPT watchdog inside FreeRTOS's own idle path
# (vPortYield in lwIP's tcpip task), which is the emulator's clock, not ours.
printf '\nCONFIG_ETH_USE_OPENETH=y\nCONFIG_LWIP_TCP_MSL=500\nCONFIG_ESP_INT_WDT=n\nCONFIG_ESP_TASK_WDT_EN=n\n' >> sdkconfig.defaults
sed -i -e 's/REQUIRES \([^)]*\))/REQUIRES \1 qemueth)/' main/CMakeLists.txt
python3 - "$REPO_ROOT" "$PORT" <<'PY'
import sys
root, port = sys.argv[1], sys.argv[2]
src = open(root + "/test/lib_mimic_urequests.npy").read().split("\n")
# the transcript is everything from the first top-level request on
start = next(i for i, l in enumerate(src) if l.startswith('r = urequests.get(base + "/hello")'))
tmpl = open(root + "/tools/esp_qemu_net/urequests_client.npy").read()
tmpl = tmpl.replace("@PORT@", port).replace("@TRANSCRIPT@", "\n".join(src[start:]).rstrip("\n"))
open("main/main.npy", "w").write(tmpl)
PY
sed -i -e "s|^REPO_ROOT=.*|REPO_ROOT=\"$REPO_ROOT\"|" build.sh

. "$ESP_IDF_DIR/export.sh" >/dev/null 2>&1
if ! PXX="$PXX" PXX_EXTRA_FLAGS="-Fu$W/$EX/main ${PXX_EXTRA_FLAGS:-}" bash build.sh >"$W/build.log" 2>&1; then
  fail_out build "$(grep -a -m3 'error' "$W/build.log" || true)" "$(tail -5 "$W/build.log")"
fi

case "$CHIP" in
  esp32s3) QEMU="$(ls "$HOME"/.espressif/tools/qemu-xtensa/*/qemu/bin/qemu-system-xtensa | head -1)" ;;
  *)       QEMU="$(ls "$HOME"/.espressif/tools/qemu-riscv32/*/qemu/bin/qemu-system-riscv32 | head -1)" ;;
esac
( cd build && python -m esptool --chip "$CHIP" merge-bin -o "$W/flash.bin" @flash_args --fill-flash-size 4MB >/dev/null 2>&1 )
"$QEMU" -M "$CHIP" -drive file="$W/flash.bin",if=mtd,format=raw -nic user,model=open_eth \
  -nographic -serial mon:stdio -monitor none >"$W/serial.log" 2>&1 &
QPID=$!
t=0
while [ $t -lt "$TIMEOUT" ] && ! grep -qa 'UREQ-COMPLETE\|Rebooting' "$W/serial.log"; do sleep 1; t=$((t + 1)); done
kill "$QPID" 2>/dev/null || true; QPID=""
tr -d '\r' < "$W/serial.log" > "$W/serial.txt"
grep -qa 'UREQ-COMPLETE' "$W/serial.txt" \
  || fail_out run "no UREQ-COMPLETE after ${t}s" "$(grep -a 'UREQ-\|assert\|Rebooting\|Guru' "$W/serial.txt" | head -5)" "$(tail -5 "$W/serial.txt")"
echo "UREQ $EX $CHIP $(grep -a '^UREQ-ETH' "$W/serial.txt")"

sed -n '/^UREQ-BEGIN$/,/^URequests OK$/p' "$W/serial.txt" | sed '1d' > "$W/chip.txt"
if [ "$ORACLE" = 0 ]; then
  echo "UREQ-ROW transcript SKIP (python3 has no requests)"
elif diff "$W/oracle.txt" "$W/chip.txt" >"$W/transcript.diff"; then
  echo "UREQ-ROW transcript OK ($(wc -l < "$W/chip.txt") lines = CPython requests)"
else
  echo "UREQ-ROW transcript FAIL"; sed 's/^/  | /' "$W/transcript.diff" | head -20
fi
d="$(grep -a '^UREQ-CENSUS dropped' "$W/serial.txt" || true)"; k="$(grep -a '^UREQ-CENSUS kept' "$W/serial.txt" || true)"
db="$(printf '%s' "$d" | sed -n 's/.* bpr=\(-\{0,1\}[0-9]*\).*/\1/p')"
kb="$(printf '%s' "$k" | sed -n 's/.* bpr=\(-\{0,1\}[0-9]*\).*/\1/p')"
if [ -n "$db" ] && [ "$db" -lt "$BOUND" ]; then echo "UREQ-ROW census OK (${d#UREQ-CENSUS }, bound $BOUND)"
else echo "UREQ-ROW census FAIL (${d#UREQ-CENSUS }, bound $BOUND)"; fi
if [ -n "$kb" ] && [ "$kb" -gt "$BOUND" ]; then echo "UREQ-ROW control OK (${k#UREQ-CENSUS }, must exceed $BOUND)"
else echo "UREQ-ROW control FAIL (${k#UREQ-CENSUS }: keeping responses did not read above the bound)"; fi
echo "UREQ-QEMU-COMPLETE"
