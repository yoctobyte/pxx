#!/bin/sh
# ESP PAL reachability census -- which platform_backend entries are REACHABLE
# from each real ESP demo.
#
# INSTRUMENT: pxx --dce (call-graph reachability). NOT a grep of call sites.
#   A grep answers "is this entry named anywhere".
#   --dce answers "is this entry reachable from THIS program's entry point".
#
# POSITIVE CONTROL (re-run it if you doubt a zero): examples/esp32/fs-c3
#   without --dce emits 114 PalBackend* bodies, INCLUDING Fork/Execve/Alarm
#   which it does not call -- without DCE the whole unit is emitted, so
#   presence-in-object is not reachability. With --dce it emits exactly 5:
#   Open Read Write Seek Close, which is what its source calls.
# NEGATIVE CONTROL: any --esp-profile=bare fixture emits 0.
#
# KNOWN LOOSENESS: riscv32 DCE over-keeps relative to xtensa
#   (bug-a-riscv32-dce-keeps-135-more-bodies-than-xtensa-on-one-program).
#   nilpy-c3 and nilpy-s3 are byte-identical sources and disagree by one body.
#   Treat every riscv32 row as an UPPER BOUND on what is reached.
#
# WHAT THIS DOES NOT MEASURE: entry. A live body is reachable-in-graph; only a
#   run records which entries were actually entered.
#
# Flags come from each demo's own build.sh invocation line -- deliberately NOT
# from a grep of flags in the file, which reads --esp-profile=bare out of the
# NilPy scripts' prose while their real compile line carries no such flag.
#
# Writes only under $W. Give it a path nothing else writes: two processes on one
# output path reports as "the output file was truncated -- usual cause: ENOSPC".
# Instrument: pxx --dce (call-graph reachability), NOT a grep of call sites.
# Flags come from each demo's own build.sh compile line, not from a flag grep.
set -u
R=/home/neo/frankB
W=/tmp/claude-1000/-home-neo-frankB/b8aadb25-016d-4305-88da-455f2ac68eae/scratchpad/palcensus.NYRFF7
export PXX="$R/compiler/pascal26"
export REPO_ROOT="$R"
mkdir -p "$W/out"

run() { # name, cwd, args...
  n=$1; d=$2; shift 2
  ( cd "$d" && "$PXX" --dce --dce-report "$@" "$W/out/b8e_$n.o" ) > "$W/out/b8e_$n.log" 2>&1
  if [ ! -f "$W/out/b8e_$n.o" ]; then
    printf '%-14s FAIL :: %s\n' "$n" "$(tail -1 "$W/out/b8e_$n.log")"; return
  fi
  live=$(nm "$W/out/b8e_$n.o" 2>/dev/null | grep -io 'PalBackend[A-Za-z0-9_]*' | sort -u)
  cnt=$(printf '%s' "$live" | grep -c .)
  printf '%-14s live=%-3s %s\n' "$n" "$cnt" "$(printf '%s' "$live" | tr '\n' ' ')"
}

for d in "$R"/examples/esp32/*/; do
  n=$(basename "$d")
  line=$(awk '/\\$/{sub(/\\$/,"");printf "%s",$0;next}{print}' "$d/build.sh" \
         | grep -E '^[[:space:]]*"\$PXX" ' | grep -v '^[[:space:]]*#' | head -1)
  case "$n" in
    nilpy*) # build.sh drives these through $ISA/$MAIN_SRC; read both from the file
      isa=$(case "$n" in *-s3|*-s2) echo "--target=xtensa --xtensa-abi=windowed --xtensa-long-calls";; *) echo "--target=riscv32";; esac)
      # shellcheck disable=SC2086
      run "$n" "$d" $isa --platform=esp --no-signals \
          -Fu"$R/lib/rtl" -Fu"$R/lib/rtl/platform/esp" main/main.npy
      continue;;
  esac
  [ -z "$line" ] && { printf '%-14s SKIP (no invocation found)\n' "$n"; continue; }
  args=$(printf '%s\n' "$line" | sed 's/^.*"\$PXX"[[:space:]]*//' \
         | sed "s#\$REPO_ROOT#$R#g" | sed 's#[[:space:]]main/main\.o.*$##')
  # shellcheck disable=SC2086
  eval "run \"\$n\" \"\$d\" $args"
done
echo "B8E-PAL-CENSUS-COMPLETE"
