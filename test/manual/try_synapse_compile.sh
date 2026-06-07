#!/usr/bin/env sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
SYNAPSE_DIR="$ROOT/external/synapse"
COMPILER="$ROOT/compiler/pascal26"
LOG="${LOG:-/tmp/pxx-synapse-compile.log}"

if [ ! -d "$SYNAPSE_DIR" ]; then
  echo "missing $SYNAPSE_DIR; run tools/install_externals.sh first" >&2
  exit 2
fi

if [ ! -x "$COMPILER" ]; then
  echo "missing $COMPILER; run make or make bootstrap first" >&2
  exit 2
fi

: > "$LOG"
status=0

for src in \
  synapse_smoke_synautil.pas \
  synapse_smoke_synaip.pas \
  synapse_smoke_synsock.pas \
  synapse_smoke_blcksock.pas
do
  echo "== $src ==" | tee -a "$LOG"
  tmp_src="$SYNAPSE_DIR/.pxx_$src"
  cp "$ROOT/test/manual/$src" "$tmp_src"
  if "$COMPILER" "$tmp_src" "/tmp/${src%.pas}" >>"$LOG" 2>&1; then
    echo "ok $src" | tee -a "$LOG"
  else
    echo "fail $src" | tee -a "$LOG"
    status=1
  fi
done

echo "log: $LOG"
exit "$status"
