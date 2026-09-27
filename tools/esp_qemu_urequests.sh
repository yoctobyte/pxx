#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# urequests (lib/rtl/mimic_urequests.py) on an emulated ESP32 -- the QEMU row
# that stands in for the silicon one (S3 as a station, a server on the
# desktop) until a board is available.
#
#   tools/esp_qemu_urequests.sh nilpy-s3|nilpy-c3 [--tls]
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
#   census      free heap over UREQ_N (1000) requests with dropped responses costs
#               under BOUND bytes per request (default 16)...
#   control     ...and keeping 50 responses costs over it, so the reading
#               can see a leak at all.
#
# --tls: the same over https://. tools/esp_qemu_net/tls_relay.py puts TLS in
# front of the same server (certificates from tools/esp_qemu_net/mkcerts.sh,
# a throwaway CA per run), the chip program is esp_qemu_net/
# urequests_tls_client.npy, and the base URL names the host BY NAME,
# 10.0.2.2.nip.io, when the host can resolve it -- so the one row also proves
# the chip's resolver (lwIP's, slirp's DNS at 10.0.2.3) end to end. With no
# DNS on the host it falls back to the address and says so (UREQ-ROW name
# SKIP). Rows added:
#   verify:good/wrongca/wrongname  ssl.SSLContext with CERT_REQUIRED accepts
#               the right CA and name, and REFUSES a wrong CA and a wrong name
#               (the controls that prove verification is done at all)
#   relay       the relay logged the handshakes, with the TLS version and
#               cipher the chip negotiated
# and the census and control run over https (UREQ_N default 100,
# UREQ_KEPT 20: each request is a full handshake, several seconds under
# emulation). UREQ_TLS_CLIENT=<file> stages another chip program in place of
# urequests_tls_client.npy, with the same placeholders, for an experiment.
# Last line: UREQ-QEMU-COMPLETE. Grep for that; the wrapper's status is not
# the verdict. Built with the PINNED compiler unless PXX says otherwise.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EX="${1:?usage: esp_qemu_urequests.sh nilpy-s3|nilpy-c3 [--tls]}"
TLS=0
case "${2:-}" in --tls) TLS=1 ;; "") ;; *) echo "ureq: unknown option ${2}" >&2; exit 2 ;; esac
case "$EX" in *-c3) CHIP=esp32c3 ;; *-s3) CHIP=esp32s3 ;; *) echo "ureq: $EX is not -c3/-s3" >&2; exit 2 ;; esac
SRC="$REPO_ROOT/examples/esp32/$EX"
[ -f "$SRC/main/main.npy" ] || { echo "ureq: $EX has no main/main.npy" >&2; exit 2; }
PXX="${PXX:-$("$REPO_ROOT/tools/pxx_stable.sh")}"
# 50, not 200: a kept response is about 1 KB, and 200 of them exhausted the
# S3 image's ~200 KB free heap on pin v438 (pxx: out of memory, reboot).
# The timeout is for an IDLE box, where the S3 run takes a few minutes;
# sharing the host with other QEMUs slowed it about 20x on 2026-09-25.
TIMEOUT="${UREQ_TIMEOUT:-1800}"
BOUND="${UREQ_BOUND:-16}"
# UREQ_N: requests in the dropped-response census (default 1000). A slow drift
# can hide inside 1000 -- a 0.6 B/request drift is 600 B there, under one heap
# block's granularity -- so the long soak runs 10000, with a free-heap
# checkpoint every N/10 (UREQ-HEAP ... delta=) to tell growth from a plateau.
# Raise UREQ_TIMEOUT with it: ~3 min per 1000 on an idle box.
# UREQ_INLINE=1: the census request is written inline at MODULE level with a
# print("x" + str(i)) per iteration -- MicroPython's usual top-level main loop.
if [ "$TLS" = 1 ]; then NREQ="${UREQ_N:-100}"; else NREQ="${UREQ_N:-1000}"; fi
KEPT="${UREQ_KEPT:-20}"
ESP_IDF_DIR="${ESP_IDF_DIR:-$HOME/esp/esp-idf}"

W="$(mktemp -d "${TMPDIR:-/tmp}/esp-qemu-ureq.XXXXXX")"
QPID=""; SPID=""; RPID=""
cleanup() {
  [ -n "$QPID" ] && kill "$QPID" 2>/dev/null
  [ -n "$SPID" ] && kill "$SPID" 2>/dev/null
  [ -n "$RPID" ] && kill "$RPID" 2>/dev/null
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

# -- --tls: a TLS relay in front of the same server, and the names
OBASE="$PORT"; CBASE="http://10.0.2.2:$PORT"
if [ "$TLS" = 1 ]; then
  bash "$REPO_ROOT/tools/esp_qemu_net/mkcerts.sh" "$W/certs" >/dev/null \
    || fail_out certs "openssl could not make the test certificates"
  python3 "$REPO_ROOT/tools/esp_qemu_net/tls_relay.py" "$W/certs/srv.pem" "$W/certs/srv.key" "$PORT" >"$W/relay.log" 2>&1 &
  RPID=$!
  for i in $(seq 40); do grep -q '^ready ' "$W/relay.log" && break; sleep 0.25; done
  TPORT="$(sed -n 's/^ready //p' "$W/relay.log" | head -n 1)"
  [ -n "$TPORT" ] || fail_out relay "the TLS relay never came up" "$(cat "$W/relay.log")"
  if [ "$(python3 -c 'import socket; print(socket.gethostbyname("10.0.2.2.nip.io"))' 2>/dev/null)" = 10.0.2.2 ]; then
    TLSHOST=10.0.2.2.nip.io; OHOST=127.0.0.1.nip.io
  else
    TLSHOST=10.0.2.2; OHOST=127.0.0.1
  fi
  OBASE="https://$OHOST:$TPORT"; CBASE="https://$TLSHOST:$TPORT"
fi

# -- the oracle: the same calls under CPython requests, against the same server
ORACLE=1
if python3 -c 'import requests' 2>/dev/null; then
  PYTHONPATH="$REPO_ROOT/test/urequests_oracle" python3 "$REPO_ROOT/test/lib_mimic_urequests.npy" "$OBASE" \
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
# the project names its in-tree components relative to examples/esp32/<dir>,
# which the staged copy is not under
sed -i -e "s|\${CMAKE_CURRENT_LIST_DIR}/../../..|$REPO_ROOT|" CMakeLists.txt
python3 - "$REPO_ROOT" "$PORT" "$NREQ" "$TLS" "$CBASE" "${TLSHOST:-}" "${TPORT:-}" "$W/certs" "$KEPT" "${UREQ_TLS_CLIENT:-$REPO_ROOT/tools/esp_qemu_net/urequests_tls_client.npy}" <<'PY'
import os, sys
root, port, n, tls, cbase, tlshost, tport, certs, keep, tlsclient = sys.argv[1:11]
src = open(root + "/test/lib_mimic_urequests.npy").read().split("\n")
# the transcript is everything from the first top-level request on
start = next(i for i, l in enumerate(src) if l.startswith('r = urequests.get(base + "/hello")'))
transcript = "\n".join(src[start:]).rstrip("\n")
if tls == "1":
    tmpl = open(tlsclient).read()
    tmpl = tmpl.replace("@BASE@", cbase).replace("@TLSHOST@", tlshost).replace("@TLSNAME@", tlshost)
    tmpl = tmpl.replace("@TLSPORT@", tport).replace("@KEEP@", keep).replace("@PORT@", port)
    tmpl = tmpl.replace("@CA_GOOD@", open(certs + "/ca.pem").read().strip())
    tmpl = tmpl.replace("@CA_WRONG@", open(certs + "/wrong-ca.pem").read().strip())
else:
    tmpl = open(root + "/tools/esp_qemu_net/urequests_client.npy").read()
    tmpl = tmpl.replace("@PORT@", port)
    if os.environ.get("UREQ_INLINE") == "1":
        tmpl = tmpl.replace("    total = total + one()  # @CENSUS-BODY@\n",
            "    r = urequests.get(base + \"/hello\")\n"
            "    total = total + r.status_code + len(r.text)\n"
            "    r.close()\n"
            "    print(\"x\" + str(i))\n")
tmpl = tmpl.replace("@TRANSCRIPT@", transcript).replace("@N@", n)
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
  -nographic -serial mon:stdio -monitor none ${UREQ_GDB_PORT:+-gdb tcp::$UREQ_GDB_PORT} >"$W/serial.log" 2>&1 &
QPID=$!
t=0; lastsz=-1; still=0
while [ $t -lt "$TIMEOUT" ] && ! grep -qa 'UREQ-COMPLETE\|Rebooting' "$W/serial.log"; do
  sleep 1; t=$((t + 1))
  # UREQ_GDB_PORT=<n>: QEMU gets a gdbserver, and a chip SILENT for UREQ_STALL_S
  # seconds (default 600: a checkpoint is N/10 requests apart) after the
  # transcript ended is read once with esp_qemu_net/stall_probe.gdb.
  if [ -n "${UREQ_GDB_PORT:-}" ] && grep -qa '^URequests OK' "$W/serial.log"; then
    sz=$(stat -c %s "$W/serial.log")
    if [ "$sz" = "$lastsz" ]; then still=$((still + 1)); else still=0; lastsz=$sz; fi
    if [ "$still" -ge "${UREQ_STALL_S:-600}" ]; then
      case "$CHIP" in esp32s3) GDB=xtensa-esp32s3-elf-gdb ;; *) GDB=riscv32-esp-elf-gdb ;; esac
      GDBBIN="$(ls "$HOME"/.espressif/tools/*-gdb/*/*/bin/$GDB | head -1)"
      echo "UREQ-STALLED after ${still}s silent at $(grep -a '^UREQ-HEAP\|^URequests OK' "$W/serial.log" | tail -1 | tr -d '\r')"
      STEPS=(); while IFS= read -r l; do STEPS+=(-ex "$l"); done < "$REPO_ROOT/tools/esp_qemu_net/stall_probe.steps"
      timeout 120 "$GDBBIN" -q -batch -ex "target remote :$UREQ_GDB_PORT" \
        -x "$REPO_ROOT/tools/esp_qemu_net/stall_probe.gdb" "${STEPS[@]}" "$(ls build/*.elf | head -1)" 2>&1 | grep -a 'STALL-GDB\|^\$\|^#' | head -120
      break
    fi
  fi
done
kill "$QPID" 2>/dev/null || true; QPID=""
tr -d '\r' < "$W/serial.log" > "$W/serial.txt"
grep -qa 'UREQ-COMPLETE' "$W/serial.txt" \
  || fail_out run "no UREQ-COMPLETE after ${t}s" "$(grep -a 'UREQ-\|assert\|Rebooting\|Guru' "$W/serial.txt" | head -5)" "$(tail -5 "$W/serial.txt")"
echo "UREQ $EX $CHIP $(grep -a '^UREQ-ETH' "$W/serial.txt") base=$CBASE"

sed -n '/^UREQ-BEGIN$/,/^URequests OK$/p' "$W/serial.txt" | sed '1d' > "$W/chip.txt"
if [ "$ORACLE" = 0 ]; then
  echo "UREQ-ROW transcript SKIP (python3 has no requests)"
elif diff "$W/oracle.txt" "$W/chip.txt" >"$W/transcript.diff"; then
  echo "UREQ-ROW transcript OK ($(wc -l < "$W/chip.txt") lines = CPython requests)"
else
  echo "UREQ-ROW transcript FAIL"; sed 's/^/  | /' "$W/transcript.diff" | head -20
fi
if [ "$TLS" = 1 ]; then
  if [ "$TLSHOST" = 10.0.2.2 ]; then echo "UREQ-ROW name SKIP (the host cannot resolve 10.0.2.2.nip.io; the address was used)"
  else echo "UREQ-ROW name OK (the transcript reached $TLSHOST through the chip's resolver)"; fi
  vrow() {   # $1 row, $2 the answer it must give
    got="$(grep -a "^UREQ-VERIFY $1 " "$W/serial.txt" | sed "s/^UREQ-VERIFY $1 //" || true)"
    if [ "$got" = "$2" ]; then echo "UREQ-ROW verify:$1 OK ($got)"
    else echo "UREQ-ROW verify:$1 FAIL (got '${got:-nothing}', want '$2')"; fi
  }
  vrow good "HTTP/1.1 200 OK"
  vrow wrongca refused
  vrow wrongname refused
  hs="$(grep -c '^TLS ' "$W/relay.log" || true)"
  if [ "$hs" -gt 0 ]; then echo "UREQ-ROW relay OK ($hs handshakes: $(grep '^TLS ' "$W/relay.log" | awk '{print $3, $4}' | sort | uniq -c | tr -s ' ' | sed 's/^ //' | tr '\n' ';'))"
  else echo "UREQ-ROW relay FAIL (no completed handshake logged)"; fi
fi
d="$(grep -a '^UREQ-CENSUS dropped' "$W/serial.txt" || true)"; k="$(grep -a '^UREQ-CENSUS kept' "$W/serial.txt" || true)"
db="$(printf '%s' "$d" | sed -n 's/.* bpr=\(-\{0,1\}[0-9]*\).*/\1/p')"
kb="$(printf '%s' "$k" | sed -n 's/.* bpr=\(-\{0,1\}[0-9]*\).*/\1/p')"
if [ -n "$db" ] && [ "$db" -lt "$BOUND" ]; then echo "UREQ-ROW census OK (${d#UREQ-CENSUS }, bound $BOUND)"
else echo "UREQ-ROW census FAIL (${d#UREQ-CENSUS }, bound $BOUND)"; fi
grep -a "^UREQ-HEAP " "$W/serial.txt" | sed "s/^/  | /" || true
if [ -n "$kb" ] && [ "$kb" -gt "$BOUND" ]; then echo "UREQ-ROW control OK (${k#UREQ-CENSUS }, must exceed $BOUND)"
else echo "UREQ-ROW control FAIL (${k#UREQ-CENSUS }: keeping responses did not read above the bound)"; fi
echo "UREQ-QEMU-COMPLETE"
