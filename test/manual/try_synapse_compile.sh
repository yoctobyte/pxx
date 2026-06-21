#!/usr/bin/env sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
SYNAPSE_DIR="$ROOT/external/synapse"
COMPILER="${COMPILER:-${PXX_STABLE:-$ROOT/stable_linux_amd64/default/pinned}}"
LOG="${LOG:-/tmp/pxx-synapse-compile.log}"
SYNAPSE_PROFILE="${SYNAPSE_PROFILE:-default}"
PROFILE_FLAGS=""

if [ ! -d "$SYNAPSE_DIR" ]; then
  echo "missing $SYNAPSE_DIR; run tools/install_externals.sh first" >&2
  exit 2
fi

if [ ! -x "$COMPILER" ]; then
  echo "missing $COMPILER; set COMPILER/PXX_STABLE or run make stabilize && make pin" >&2
  exit 2
fi

case "$SYNAPSE_PROFILE" in
  default)
    ;;
  posix)
    # Manual stand-in for the future scoped Synapse library profile.
    # Keeps this harness useful without pretending the manifest feature exists.
    PROFILE_FLAGS="-dPOSIX -dUNIX -dDELPHI -dDELPHICOMPILER -dDELPHI16 -dDELPHIXE2"
    ;;
  *)
    echo "unknown SYNAPSE_PROFILE=$SYNAPSE_PROFILE (use default or posix)" >&2
    exit 2
    ;;
esac

: > "$LOG"
status=0
echo "compiler: $COMPILER" | tee -a "$LOG"
echo "profile: $SYNAPSE_PROFILE" | tee -a "$LOG"

for src in \
  synapse_smoke_synautil.pas \
  synapse_smoke_synaip.pas \
  synapse_smoke_synsock.pas \
  synapse_smoke_blcksock.pas
do
  echo "== $src ==" | tee -a "$LOG"
  tmp_src="$SYNAPSE_DIR/.pxx_$src"
  cp "$ROOT/test/manual/$src" "$tmp_src"
  if "$COMPILER" $PROFILE_FLAGS "$tmp_src" "/tmp/${src%.pas}" >>"$LOG" 2>&1; then
    echo "ok $src" | tee -a "$LOG"
  else
    echo "fail $src" | tee -a "$LOG"
    status=1
  fi
done

echo "log: $LOG"
exit "$status"
