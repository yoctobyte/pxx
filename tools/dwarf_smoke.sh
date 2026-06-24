#!/usr/bin/env bash
# DWARF Tier 1 (-g) smoke gate. Builds a tiny program with -g and asserts:
#   1. readelf --debug-dump=decodedline shows line rows for the source file
#   2. (if gdb present) a line breakpoint resolves + hits, and `bt` prints file:line
# x86-64 only — Tier 1 emits debug info on that backend alone.
#
# Usage: tools/dwarf_smoke.sh <path-to-pxx-compiler>
set -u
PXX="${1:?usage: dwarf_smoke.sh <compiler>}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
SRC="$TMP/dbgsmoke.pas"
EXE="$TMP/dbgsmoke"

cat > "$SRC" <<'EOF'
program dbgsmoke;
var i: Integer;
begin
  i := 0;
  while i < 3 do
  begin
    writeln('i=', i);
    i := i + 1;
  end;
  writeln('done');
end.
EOF
# The writeln is on line 7 — the breakpoint target.
BPLINE=7

"$PXX" -g "$SRC" "$EXE" >/dev/null 2>&1 || { echo "dwarf-g: FAIL — compile -g errored"; exit 1; }

# Runtime behaviour must be identical to a normal build.
OUT="$("$EXE")"
EXP="$(printf 'i=0\ni=1\ni=2\ndone')"
[ "$OUT" = "$EXP" ] || { echo "dwarf-g: FAIL — runtime output changed under -g"; echo "got: $OUT"; exit 1; }

# 1. Line table present and references the source file.
if command -v readelf >/dev/null 2>&1; then
  DL="$(readelf --debug-dump=decodedline "$EXE" 2>/dev/null)"
  echo "$DL" | grep -q 'dbgsmoke.pas' || { echo "dwarf-g: FAIL — no .debug_line rows for source"; exit 1; }
  echo "$DL" | grep -qE "[[:space:]]$BPLINE[[:space:]]+0x" || { echo "dwarf-g: FAIL — line $BPLINE not in line table"; exit 1; }
else
  echo "dwarf-g: WARN — readelf not found, skipping line-table check"
fi

# 2. gdb sets + hits a line breakpoint and bt shows file:line.
if command -v gdb >/dev/null 2>&1; then
  GLOG="$(gdb -q -batch -ex "set debuginfod enabled off" \
    -ex "break dbgsmoke.pas:$BPLINE" -ex "run" -ex "bt" "$EXE" 2>/dev/null)"
  echo "$GLOG" | grep -qE "Breakpoint 1 at .*dbgsmoke.pas, line $BPLINE" \
    || { echo "dwarf-g: FAIL — gdb could not resolve line breakpoint"; echo "$GLOG"; exit 1; }
  echo "$GLOG" | grep -qE "Breakpoint 1,.*dbgsmoke.pas:$BPLINE" \
    || { echo "dwarf-g: FAIL — gdb breakpoint did not hit at file:line"; echo "$GLOG"; exit 1; }
  echo "$GLOG" | grep -qE "dbgsmoke.pas:$BPLINE" \
    || { echo "dwarf-g: FAIL — bt does not show file:line"; echo "$GLOG"; exit 1; }
else
  echo "dwarf-g: WARN — gdb not found, skipping breakpoint check"
fi

echo "dwarf-g: OK"
