#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# DWARF Tier 1-3 (-g) smoke gate. Builds a tiny program with -g and asserts:
#   T1  readelf --debug-dump=decodedline shows line rows for the source
#   T1  gdb resolves+hits a line breakpoint, step tracks source lines
#   T2  bt shows PXX function names + file:line frames
#   T3  params/locals/record fields print with correct values
# x86-64 only — debug info is emitted on that backend alone.
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
type
  TPoint = record
    x, y: Integer;
  end;

function Add(a, b: Integer): Integer;
var local: Integer;
begin
  local := a + b;
  Add := local;
end;

var
  pt: TPoint;
  s: Integer;
begin
  pt.x := 3;
  pt.y := 4;
  s := Add(pt.x, pt.y);
  writeln('i=', s);
end.
EOF
# Add's body is line 10; the program writeln is line 21.
ADDLINE=10

"$PXX" -g "$SRC" "$EXE" >/dev/null 2>&1 || { echo "dwarf-g: FAIL — compile -g errored"; exit 1; }

OUT="$("$EXE")"
[ "$OUT" = "i=7" ] || { echo "dwarf-g: FAIL — runtime output changed under -g (got: $OUT)"; exit 1; }

# T1: line table present and references the source file.
if command -v readelf >/dev/null 2>&1; then
  DL="$(readelf --debug-dump=decodedline "$EXE" 2>/dev/null)"
  echo "$DL" | grep -q 'dbgsmoke.pas' || { echo "dwarf-g: FAIL — no .debug_line rows for source"; exit 1; }
  echo "$DL" | grep -qE "[[:space:]]$ADDLINE[[:space:]]+0x" || { echo "dwarf-g: FAIL — line $ADDLINE not in line table"; exit 1; }
else
  echo "dwarf-g: WARN — readelf not found, skipping line-table check"
fi

# T1-T3 via gdb: break in Add (line:file form, the robust path), check name in
# bt, args, a local, and a record field in the caller frame.
if command -v gdb >/dev/null 2>&1; then
  GLOG="$(gdb -q -batch -ex "set debuginfod enabled off" \
    -ex "break dbgsmoke.pas:$ADDLINE" -ex "run" -ex "bt" \
    -ex "print a" -ex "print b" -ex "up" -ex "print pt" \
    "$EXE" 2>/dev/null)"
  echo "$GLOG" | grep -qE "Breakpoint 1,.*Add .*dbgsmoke.pas:$ADDLINE" \
    || { echo "dwarf-g: FAIL — gdb did not hit Add at file:line with function name"; echo "$GLOG"; exit 1; }
  echo "$GLOG" | grep -qE "dbgsmoke .*dbgsmoke.pas:" \
    || { echo "dwarf-g: FAIL — bt missing caller frame (program body)"; echo "$GLOG"; exit 1; }
  echo "$GLOG" | grep -qE '\$1 = 3' \
    || { echo "dwarf-g: FAIL — param a not readable (expected 3)"; echo "$GLOG"; exit 1; }
  echo "$GLOG" | grep -qE 'x = 3, y = 4' \
    || { echo "dwarf-g: FAIL — record fields not inspectable (expected x=3,y=4)"; echo "$GLOG"; exit 1; }
  # CFI: the backtrace must terminate cleanly — no junk "?? ()" frame past the
  # program body (.debug_frame FDEs + RA-undefined on the main body).
  echo "$GLOG" | grep -qE '\?\? \(\)' \
    && { echo "dwarf-g: FAIL — junk frame in bt (CFI/.debug_frame missing)"; echo "$GLOG"; exit 1; }
  # Crash backtrace: a SIGSEGV must unwind to named frames with file:line.
  CSRC="$TMP/dbgcrash.pas"; CEXE="$TMP/dbgcrash"
  cat > "$CSRC" <<'EOC'
program dbgcrash;
type PInt = ^Integer;
procedure Boom(p: PInt);
begin
  p^ := 5;
end;
begin
  Boom(nil);
end.
EOC
  "$PXX" -g "$CSRC" "$CEXE" >/dev/null 2>&1 || { echo "dwarf-g: FAIL — crash sample compile errored"; exit 1; }
  CLOG="$(gdb -q -batch -ex "set debuginfod enabled off" -ex run -ex bt "$CEXE" 2>/dev/null)"
  echo "$CLOG" | grep -qE "Boom .*dbgcrash.pas:5" \
    || { echo "dwarf-g: FAIL — crash bt missing faulting frame"; echo "$CLOG"; exit 1; }
else
  echo "dwarf-g: WARN — gdb not found, skipping breakpoint/inspection checks"
fi

# Cross targets: structural check (portable — readelf is arch-independent). Each
# -g build must carry a populated .debug_line + a .debug_frame CIE. Full runtime
# cross-debug (qemu gdbstub + gdb-multiarch) is validated manually, not gated.
if command -v readelf >/dev/null 2>&1; then
  for T in aarch64 i386 arm32; do
    TEXE="$TMP/dbgsmoke.$T"
    "$PXX" -g --target=$T "$SRC" "$TEXE" >/dev/null 2>&1 || { echo "dwarf-g: FAIL — -g --target=$T compile errored"; exit 1; }
    readelf --debug-dump=decodedline "$TEXE" 2>/dev/null | grep -qE "[[:space:]]$ADDLINE[[:space:]]+0x" \
      || { echo "dwarf-g: FAIL — $T: line $ADDLINE missing from .debug_line"; exit 1; }
    readelf --debug-dump=frames "$TEXE" 2>/dev/null | grep -q "CIE" \
      || { echo "dwarf-g: FAIL — $T: no .debug_frame CIE"; exit 1; }
  done

  # THE OTHER HALF OF THE SET, and until 2026-09-01 nothing asserted it. Every
  # row above fails by LOSING debug info and none of them can fail by gaining it
  # somewhere it does not belong, so a change that widened the DWARF target set
  # to the ESP ISAs passed the whole suite. xtensa and riscv32 are excluded
  # deliberately (windowed / no-frame-pointer ABI, no gdb-over-qemu line path),
  # and an exclusion nothing checks is a comment, not a gate.
  #
  # WHICH ROW ACTUALLY DISCRIMINATES, measured rather than assumed. The 32-bit
  # writer gates on `DbgArchSupported and (not EspBareBoot)`, so ANY bare-profile
  # build emits no debug sections no matter what the target set says. Widening
  # DbgArchSupported to both ESP ISAs and rebuilding:
  #
  #   riscv32 hosted -> 4 sections   CAUGHT
  #   riscv32 bare   -> 0 sections   masked by EspBareBoot
  #   xtensa  bare   -> 0 sections   masked by EspBareBoot
  #
  # and xtensa has no hosted exec path at all (a plain -g --target=xtensa refuses
  # on external symbols before any writer runs). So the riscv32 row is the set
  # assertion; the xtensa row asserts only that -g still COMPILES for xtensa,
  # which is worth a second but is not a statement about the target set. Saying
  # so here because a row that cannot fail prints PASS exactly like one that can.
  #
  # THE LIST HERE IS THE SPEC and it is the SECOND statement of it on purpose --
  # DbgArchSupported in elfwriter.inc is the first, and the two are meant to be
  # edited in the same commit. That is a different animal from the three
  # undeclared copies this replaced, where the authority was dead code and the
  # live gates had drifted:
  # bug-a-the-dwarf-target-set-is-written-down-three-times-and-the-authority-is-dead-code
  for T in riscv32 xtensa; do
    TEXE="$TMP/dbgsmoke.$T"
    EXTRA=""
    [ "$T" = xtensa ] && EXTRA="--platform=esp --esp-profile=bare"
    "$PXX" -g --target=$T $EXTRA "$SRC" "$TEXE" >/dev/null 2>&1 \
      || { echo "dwarf-g: FAIL — -g --target=$T $EXTRA compile errored (the row cannot answer)"; exit 1; }
    N=$(readelf -SW "$TEXE" 2>/dev/null | grep -c '\.debug_')
    [ "$N" = 0 ] || { echo "dwarf-g: FAIL — $T emitted $N .debug_* section(s); the DWARF target set excludes it. If that is intentional, change DbgArchSupported and this list together."; exit 1; }
  done
  echo "dwarf-g: cross target set ok — aarch64/i386/arm32 carry DWARF; riscv32 carries none (the discriminating row); xtensa -g compiles and is masked by EspBareBoot"
fi

# A CYCLIC type graph — `TB = class;` forward, TA holds a TB, TB holds a TA —
# is legal Pascal and is exactly what the forward declaration exists to allow.
# The type walker used to register a struct only AFTER walking its fields, so it
# re-entered itself and ran the COMPILER's stack out (SIGSEGV, no diagnostic).
# Synapse's TTCPBlockSocket <-> TCustomSSL is this shape, so no Synapse program
# could be built with debug info at all.
MSRC="$TMP/dbgmutu.pas"; MEXE="$TMP/dbgmutu"
cat > "$MSRC" <<'EOM'
program dbgmutu;
type
  TB = class;
  TA = class
    b: TB;
    v: Integer;
  end;
  TB = class
    a: TA;
    w: Integer;
  end;
var x: TA;
begin
  x := TA.Create;
  x.v := 41;
  x.b := TB.Create;
  x.b.w := 7;
  x.b.a := x;
  writeln('m=', x.v + x.b.w);
end.
EOM
"$PXX" -g "$MSRC" "$MEXE" >/dev/null 2>&1 || { echo "dwarf-g: FAIL — cyclic class types crashed the compiler under -g"; exit 1; }
MOUT="$("$MEXE")"
[ "$MOUT" = "m=48" ] || { echo "dwarf-g: FAIL — cyclic sample output wrong (got: $MOUT)"; exit 1; }
if command -v readelf >/dev/null 2>&1; then
  MDI="$(readelf --debug-dump=info "$MEXE" 2>/dev/null)"
  # each type described exactly ONCE, and both are present
  for N in TA TB; do
    C="$(echo "$MDI" | grep -cE "DW_AT_name[[:space:]]+: $N\$")"
    [ "$C" = "1" ] || { echo "dwarf-g: FAIL — $N described $C times, expected 1"; exit 1; }
  done
fi
if command -v gdb >/dev/null 2>&1; then
  MLOG="$(gdb -q -batch -ex "set debuginfod enabled off" \
    -ex "break dbgmutu.pas:19" -ex run -ex "print x.v" -ex "print x.b.w" "$MEXE" 2>/dev/null)"
  echo "$MLOG" | grep -qE '\$2 = 7' \
    || { echo "dwarf-g: FAIL — cannot read through the type cycle (expected 7)"; echo "$MLOG"; exit 1; }
fi

echo "dwarf-g: OK"
