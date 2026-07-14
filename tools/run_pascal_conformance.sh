#!/usr/bin/env sh
# SPDX-License-Identifier: MPL-2.0
# FPC test-suite conformance runner (feature-pascal-corpus-fpc-testsuite, rung 1
# of feature-pascal-corpus-expansion). Pascal analog of run_c_conformance.sh.
#
# Runs a curated subset of FPC's own tests/test/*.pp conformance programs
# against the pxx Pascal frontend. Contract (mirroring FPC's dotest):
#   - default: program must compile, run, and exit 0
#   - { %FAIL }   : the compile must be REJECTED (accepting it = pxx bug)
#   - { %NORUN }  : compile-only
#   - { %RESULT=n }: expected exit code n instead of 0
# Tests gated on other CPUs/targets/FPC-versions or needing suite infra we
# don't model (%OPT, %recompile, %files, %needlibrary, %interactive, %wpo)
# are auto-skipped and counted separately from the curated skip list.
#
# Skips are EXPLICIT: test/pascal-conformance/pxx.skip lists one test per line
# as "name.pp<TAB>reason"; anything not passing, not auto-gated, and not
# listed = FAIL.
#
# Usage: tools/run_pascal_conformance.sh [compiler] [suite-dir] [--shard I/N] [--all] [--only GLOB]
#   compiler   default compiler/pascal26
#   suite-dir  default library_candidates/fpc-testsuite/tests/test
#   --shard I/N  run only tests with (index mod N) == I (0-based)
#   --all        run every top-level *.pp instead of the curated categories
#   --only GLOB  run only tests matching GLOB (e.g. 'tgeneric*')
set -u

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
CC="$ROOT/compiler/pascal26"
# FPC-parity flags: strict diagnostics that are opt-in in the PXX dialect
# (lax first-match case labels are a deliberate divergence -- see pxx.skip
# "dialect-pass" entries and devdocs ticket bug-pascal-missing-diagnostics-fail-tests).
CCFLAGS="--strict-case --strict-operator"
SUITE="$ROOT/library_candidates/fpc-testsuite/tests/test"
SHARD_I=0; SHARD_N=1
ALL=0; ONLY=""; REPORT=""
case "${1:-}" in ''|--*) ;; *) CC="$1"; shift ;; esac
case "${1:-}" in ''|--*) ;; *) SUITE="$1"; shift ;; esac
while [ $# -gt 0 ]; do
  case "$1" in
    --shard)   SHARD_I="${2%%/*}"; SHARD_N="${2##*/}"; shift ;;
    --shard=*) v="${1#--shard=}"; SHARD_I="${v%%/*}"; SHARD_N="${v##*/}" ;;
    --all)     ALL=1 ;;
    --only)    ONLY="$2"; shift ;;
    --only=*)  ONLY="${1#--only=}" ;;
    --report)  REPORT="$2"; shift ;;   # per-test TSV: status name category tag reason
    --report=*) REPORT="${1#--report=}" ;;
    *) echo "run_pascal_conformance: unknown option $1" >&2; exit 2 ;;
  esac
  shift
done
SKIPLIST="$ROOT/test/pascal-conformance/pxx.skip"
LABEL="test-pascal-conformance"
WORK="${TMPDIR:-/tmp}/pxx_pas_conformance.$$"
TIMEOUT_S="$(awk -v s="${TESTMGR_TIME_SCALE:-1}" 'BEGIN { t=10*s; printf "%d", (t<10 ? 10 : t) }')"

# Curated categories (ticket scope): what self-host never exercises.
# Expand as rungs clear.
CATEGORIES="tgeneric tgenconstraint tgenfunc tobject tclass tprop texception
toperator tmoperator tstring tarray tarrconstr tcase tset tenum trange tint64
tforin tinterface terecs tprocvar tover tdefault tstatic tsealed"

if [ ! -d "$SUITE" ]; then
  echo "$LABEL: SKIP — no suite at $SUITE (run tools/install_lib_candidates.sh fpc-testsuite)"
  exit 0
fi
[ -x "$CC" ] || { echo "$LABEL: compiler not found: $CC" >&2; exit 2; }

mkdir -p "$WORK"
trap 'rm -rf "$WORK"' EXIT

# Extract "%NAME" / "%NAME=VALUE" directives from a test's leading comment
# block (FPC dotest convention: { %fail }, { %cpu=x86_64 }, ...). Prints
# NAME=VALUE (NAME uppercased, VALUE may be empty), one per line.
directives() {
  sed -n '1,40p' "$1" | tr -d '\r' |
  sed -n 's/^[ \t]*{[ \t]*%\([A-Za-z_]*\)[ \t]*=\{0,1\}[ \t]*\([^}]*\)}.*/\1=\2/p' |
  awk -F= '{ n=toupper($1); v=$2; sub(/[ \t]+$/,"",v); print n "=" v }'
}

list_tests() {
  if [ -n "$ONLY" ]; then
    ( cd "$SUITE" && ls $ONLY 2>/dev/null ) | grep '\.pp$'
  elif [ "$ALL" = "1" ]; then
    ( cd "$SUITE" && ls *.pp 2>/dev/null )
  else
    for c in $CATEGORIES; do
      ( cd "$SUITE" && ls "$c"*.pp 2>/dev/null )
    done
  fi | grep -v '^u' | sort -u
}

# --- per-test report (feature-testmgr-fpc-compare-and-web-dashboard) -------
# category = the CATEGORIES prefix the name starts with (else "other").
# tag: skip reasons may lead with "wontfix:" (tests FPC internals / intentional
# divergence — never counts as a failure) or "gap:" (real unimplemented
# feature); untagged skips are "untriaged". Non-skip rows carry tag "-".
cat_of() {
  for c in $CATEGORIES; do
    case "$1" in ${c}*) printf '%s' "$c"; return ;; esac
  done
  printf 'other'
}
emit() {  # emit STATUS NAME REASON
  [ -n "$REPORT" ] || return 0
  _st="$1"; _nm="$2"; _rs="$3"; _tag="-"
  case "$_rs" in
    wontfix:*) _tag="wontfix"; _rs="$(printf '%s' "$_rs" | sed 's/^wontfix:[ \t]*//')" ;;
    gap:*)     _tag="gap";     _rs="$(printf '%s' "$_rs" | sed 's/^gap:[ \t]*//')" ;;
    *) [ "$_st" = skip ] && _tag="untriaged" ;;
  esac
  # strip stray tabs from reason so the TSV stays 5-column
  _rs="$(printf '%s' "$_rs" | tr '\t' ' ')"
  printf '%s\t%s\t%s\t%s\t%s\n' "$_st" "$_nm" "$(cat_of "$_nm")" "$_tag" "$_rs" >> "$REPORT"
}
if [ -n "$REPORT" ]; then
  : > "$REPORT"
  printf '# status\tname\tcategory\ttag\treason\n' > "$REPORT"
fi

pass=0; fail=0; skip=0; auto=0; failed=""; idx=-1

for name in $(list_tests); do
  src="$SUITE/$name"
  [ -f "$src" ] || continue
  idx=$((idx+1))
  [ $((idx % SHARD_N)) = "$SHARD_I" ] || continue

  # ---- directive gates (suite conventions we don't model → auto-skip) ----
  dirs="$(directives "$src")"
  expect_fail=0; norun=0; want_rc=0; gate=""
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    n="${d%%=*}"; v="${d#*=}"
    case "$n" in
      FAIL)   expect_fail=1 ;;
      NORUN)  norun=1 ;;
      RESULT) want_rc="$v" ;;
      CPU)    case ",$v," in *[,\ ]x86_64[,\ ]*|*,x86_64,*|,x86_64,) ;; *) gate="cpu=$v" ;; esac ;;
      SKIPCPU) case ",$v," in *,x86_64,*) gate="skipcpu" ;; esac ;;
      TARGET) case ",$v," in *,linux,*|*,unix,*) ;; *) gate="target=$v" ;; esac ;;
      SKIPTARGET) case ",$v," in *,linux,*|*,unix,*) gate="skiptarget" ;; esac ;;
      OPT|NEEDLIBRARY|RECOMPILE|INTERACTIVE|FILES|WPOPARAS|WPOPASSES|DELFILES|KNOWNRUNERROR|TIMEOUT|VERSION|MAXVERSION|GRAPH|FILEDENIED)
              gate="$(echo "$n" | tr 'A-Z' 'a-z')" ;;
    esac
  done <<EOF
$dirs
EOF
  if [ -n "$gate" ]; then
    auto=$((auto+1))
    emit auto "$name" "$gate"
    continue
  fi

  # ---- curated skip list ----
  reason=""
  if [ -f "$SKIPLIST" ]; then
    reason="$(awk -v n="$name" '$1==n { $1=""; sub(/^[ \t]+/,""); print; exit }' "$SKIPLIST")"
  fi
  if [ -n "$reason" ]; then
    skip=$((skip+1))
    emit skip "$name" "$reason"
    echo "SKIP $name — $reason"
    continue
  fi

  # ---- compile ----
  bin="$WORK/${name%.pp}"
  compile_ok=0
  if sed -n '1,40p' "$src" | grep -qi '^[ \t]*unit[ \t]'; then
    # UNIT-shaped test (FPC compiles units standalone): synthesize a driver
    # program that uses it, so the unit's whole body is compiled. Compile-only
    # (the suite's unit tests carry their checks in callers we don't have).
    uname="${name%.pp}"
    cp "$src" "$WORK/$uname.pas"
    printf 'program drv_%s;\nuses %s;\nbegin\nend.\n' "$uname" "$uname" > "$WORK/drv_$uname.pas"
    ( cd "$WORK" && timeout "$TIMEOUT_S" "$CC" $CCFLAGS "drv_$uname.pas" "$bin" ) > "$WORK/cc.log" 2>&1 || compile_ok=1
    norun=1
  else
    ( cd "$SUITE" && timeout "$TIMEOUT_S" "$CC" $CCFLAGS "$name" "$bin" ) > "$WORK/cc.log" 2>&1 || compile_ok=1
  fi

  if [ "$expect_fail" = "1" ]; then
    if [ "$compile_ok" != "0" ]; then
      pass=$((pass+1)); emit pass "$name" ""
    else
      fail=$((fail+1)); failed="$failed $name(accepted-invalid)"
      emit fail "$name" "accepted-invalid: %FAIL test compiled"
      echo "FAIL $name — %FAIL test compiled (must be rejected)"
    fi
    continue
  fi

  if [ "$compile_ok" != "0" ]; then
    fail=$((fail+1)); failed="$failed $name(compile)"
    emit fail "$name" "compile error"
    echo "FAIL $name — compile error:"
    sed -n '1,4p' "$WORK/cc.log" | sed 's/^/    /'
    continue
  fi
  [ "$norun" = "1" ] && { pass=$((pass+1)); emit pass "$name" ""; continue; }

  # ---- run ----
  ( cd "$WORK" && timeout "$TIMEOUT_S" "$bin" ) > "$WORK/out.txt" 2>&1
  rc=$?
  if [ "$rc" != "$want_rc" ]; then
    fail=$((fail+1)); failed="$failed $name(exit=$rc)"
    emit fail "$name" "runtime: exit code $rc (want $want_rc)"
    echo "FAIL $name — exit code $rc (want $want_rc)"
    sed -n '1,4p' "$WORK/out.txt" | sed 's/^/    /'
    continue
  fi
  pass=$((pass+1)); emit pass "$name" ""
done

echo "$LABEL: $pass pass, $fail fail, $skip skip, $auto auto-gated (of $((pass+fail+skip+auto)))"
if [ "$fail" != "0" ]; then
  echo "$LABEL: FAILURES:$failed"
  exit 1
fi
