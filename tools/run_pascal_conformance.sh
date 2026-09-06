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
# Absolutise both IMMEDIATELY, before anything can cd.
#
# Every compile below runs from inside another directory (`cd "$SUITE"`, `cd
# "$WORK"`), so a relative $CC stops resolving there — and the failure surfaces
# per test as `compile error: timeout: failed to execute process`, i.e. as a
# COMPILER bug, for every test at once. Measured: `./compiler/pascal26` gives
# "10 pass, 51 fail" where the absolute path gives "61 pass, 0 fail".
#
# The defaults are absolute and testmgr passes absolute paths, so only an
# operator invoking this by hand hits it — which is precisely the debugging
# position where a wall of red is most expensive, because it reads as "my change
# broke 51 tests" at the exact moment someone is looking for what their change
# broke.
case "$CC"    in /*) ;; *) CC="$(CDPATH= cd -- "$(dirname -- "$CC")" 2>/dev/null && pwd)/$(basename -- "$CC")" ;; esac
case "$SUITE" in /*) ;; *) SUITE="$(CDPATH= cd -- "$SUITE" 2>/dev/null && pwd)" ;; esac
while [ $# -gt 0 ]; do
  case "$1" in
    --shard)   SHARD_I="${2%%/*}"; SHARD_N="${2##*/}"; shift ;;
    --shard=*) v="${1#--shard=}"; SHARD_I="${v%%/*}"; SHARD_N="${v##*/}" ;;
    --all)     ALL=1 ;;
    --retry-skips) RETRY_SKIPS=1 ;;   # re-attempt the skip list; see the summary note below
    --only)    ONLY="$2"; shift ;;
    --only=*)  ONLY="${1#--only=}" ;;
    --report)  REPORT="$2"; shift ;;   # per-test TSV: status name category tag reason
    --report=*) REPORT="${1#--report=}" ;;
    # --diag-map: one line per skip row, "name<TAB>first compiler diagnostic"
    # (or "<compiles clean>"). NOT the verdict -- the DIAGNOSTIC, which is the
    # only thing that moves when a skip reason stops being true while the row
    # keeps failing. See the note above the capture below.
    --diag-map)   DIAGMAP="$2"; shift ;;
    --diag-map=*) DIAGMAP="${1#--diag-map=}" ;;
    *) echo "run_pascal_conformance: unknown option $1" >&2; exit 2 ;;
  esac
  shift
done
SKIPLIST="$ROOT/test/pascal-conformance/pxx.skip"
DIAGMAP="${DIAGMAP:-}"
# A MAP BUILT WITHOUT ATTEMPTING THE ROWS WOULD BE EMPTY AND LOOK CLEAN, which
# is the collision this repo keeps paying for: "nothing changed" and "nothing
# was measured" must not produce the same artefact. So --diag-map REQUIRES
# --retry-skips rather than quietly writing a file of nothing.
if [ -n "$DIAGMAP" ] && [ "${RETRY_SKIPS:-0}" != "1" ]; then
  echo "run_pascal_conformance: --diag-map requires --retry-skips (the skip rows must actually be compiled for their diagnostic to exist)" >&2
  exit 2
fi
LABEL="test-pascal-conformance"
WORK="${TMPDIR:-/tmp}/pxx_pas_conformance.$$"
# BOTH scales, not just the hardware one. TESTMGR_LOAD_SCALE (= cap/cores) is
# the live concurrency factor testmgr exports, and load_scale()'s own docstring
# names this exact consumer: it exists because oversubscription "starves a
# qemu-user conformance shard's per-program `timeout` and false-REDs the whole
# shard with exit 124". This runner was reading TIME_SCALE only, so on a box
# that is BUSY rather than SLOW the factor read 1.00 and a 10s inner budget
# stayed 10s under 2x oversubscription. run_c_conformance.sh next door already
# does it correctly and this is its sibling arm; run_sqlite_thread_test.sh was
# the same defect, fixed by frankT at ea7cb2aa2.
#
# No inner cap here, unlike the sqlite runner: its inner budget was approaching
# the 240s OUTER qemu-class timeout, where a job-level kill discards the line
# the runner exists to print. Conformance's outer class budget is 1200s, so a
# genuinely hung program is still caught there — the inner budget only has to
# clear the slowest HONEST program under load, not police hangs.
TIMEOUT_S="$(awk -v s="${TESTMGR_TIME_SCALE:-1}" -v l="${TESTMGR_LOAD_SCALE:-1}" \
  'BEGIN { t=10*s*l; printf "%d", (t<10 ? 10 : t) }')"

# Curated categories (ticket scope): what self-host never exercises.
# Expand as rungs clear.
CATEGORIES="tgeneric tgenconstraint tgenfunc tobject tclass tprop texception
toperator tmoperator tstring tarray tarrconstr tcase tset tenum trange tint64
tforin tinterface terecs tprocvar tover tdefault tstatic tsealed"

if [ ! -d "$SUITE" ]; then
  echo "$LABEL: SKIP — no suite at $SUITE (run tools/install_lib_candidates.sh fpc-testsuite)"
  exit 0
fi
# Checked AFTER absolutisation, which is what makes the check meaningful: it
# used to run against the path as given, so a relative path that would not
# resolve once we cd'd passed here and failed 51 times later, one test at a
# time. A compiler that cannot be executed is a hard error, never a per-test
# compile failure — the whole difference between "your setup is wrong" and
# "your compiler is broken".
[ -x "$CC" ] || { echo "$LABEL: compiler not found or not executable: $CC" >&2; exit 2; }

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
# Counter routing. Under --retry-skips a row that was skip-listed is being
# attempted on purpose, so its outcome belongs in the retry tally and NOT in the
# conformance verdict: a pass means the skip entry is STALE (burn it), a fail
# means the gap is still there (expected, not a regression).
bump_pass() {
  if [ "${retrying:-0}" = "1" ]; then
    stale=$((stale+1)); stale_list="$stale_list $name"
  else
    pass=$((pass+1))
  fi
}
bump_fail() {  # bump_fail TAG
  if [ "${retrying:-0}" = "1" ]; then
    stillgap=$((stillgap+1))
  else
    fail=$((fail+1)); failed="$failed $1"
  fi
}

emit() {  # emit STATUS NAME REASON
  [ -n "$REPORT" ] || return 0
  _st="$1"; _nm="$2"; _rs="$3"; _tag="-"
  # FOUR TAGS ARE IN USE AND THIS KNEW TWO. Measured 2026-09-06: pxx.skip
  # carries gap (86), wontfix (22), decided (5) and accepts-invalid (2). The
  # file's own header documents only the first two, so the last seven rows were
  # reported to the dashboard as "untriaged" -- i.e. as rows nobody had judged --
  # with their tag still glued to the front of the reason text. A tag the tool
  # does not know was silently downgraded to NO TAG, which is the sentinel
  # collision this repo keeps paying for: "not classified" and "classified as
  # something I do not recognise" are different facts and must not share a value.
  #
  # So an unrecognised leading tag is reported AS ITSELF, prefixed, rather than
  # absorbed -- a new tag shows up in the dashboard as a name nobody expected
  # instead of vanishing into the untriaged bucket. "untriaged" now means
  # genuinely untagged. Deliberately conservative about what counts as a tag:
  # a leading lowercase word of <=20 chars followed by a colon, so a reason
  # beginning "note: ..." is caught as an unknown tag and looked at, while
  # prose containing a colon later in the line is untouched.
  case "$_rs" in
    wontfix:*)         _tag="wontfix";         _rs="$(printf '%s' "$_rs" | sed 's/^wontfix:[ \t]*//')" ;;
    gap:*)             _tag="gap";             _rs="$(printf '%s' "$_rs" | sed 's/^gap:[ \t]*//')" ;;
    decided:*)         _tag="decided";         _rs="$(printf '%s' "$_rs" | sed 's/^decided:[ \t]*//')" ;;
    accepts-invalid:*) _tag="accepts-invalid"; _rs="$(printf '%s' "$_rs" | sed 's/^accepts-invalid:[ \t]*//')" ;;
    *)
      _lead="$(printf '%s' "$_rs" | sed -n 's/^\([a-z][a-z-]\{0,19\}\):.*/\1/p')"
      if [ -n "$_lead" ]; then
        _tag="UNKNOWN-TAG:$_lead"
        _rs="$(printf '%s' "$_rs" | sed "s/^$_lead:[ \t]*//")"
      elif [ "$_st" = skip ]; then
        _tag="untriaged"
      fi
      ;;
  esac
  # strip stray tabs from reason so the TSV stays 5-column
  _rs="$(printf '%s' "$_rs" | tr '\t' ' ')"
  printf '%s\t%s\t%s\t%s\t%s\n' "$_st" "$_nm" "$(cat_of "$_nm")" "$_tag" "$_rs" >> "$REPORT"
}
if [ -n "$REPORT" ]; then
  : > "$REPORT"
  printf '# status\tname\tcategory\ttag\treason\n' > "$REPORT"
fi
if [ -n "$DIAGMAP" ]; then
  : > "$DIAGMAP"
  printf '# name\tfirst-diagnostic  (run: %s)\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$DIAGMAP"
fi

pass=0; fail=0; skip=0; auto=0; failed=""; idx=-1
retried=0; stale=0; stillgap=0; stale_list=""; retrying=0   # --retry-skips tallies (set -u is on)

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
  # ---- a UNIT source is not evaluable here, and a %FAIL one passes VACUOUSLY ----
  # FPC's dotest compiles a unit standalone; pxx has no standalone unit compile
  # and answers "this file is a unit, not a program" for every one of them. That
  # is a refusal, so under the %FAIL contract ("the compile must be REJECTED")
  # EVERY unit-source %FAIL row passes -- whatever it contains, including a row
  # whose subject we get wrong. A guard that cannot fail, and it printed PASS:
  # measured 2026-09-06, tgeneric105 was being counted as a pass on exactly this,
  # and tgenfunc14/17/18 carried curated skip reasons describing a dialect-pass
  # the compiler never reached the source to have.
  #
  # Auto-gated rather than skip-listed because it is the same KIND of thing the
  # gates above are: suite infra we do not model, not a triaged gap. 4 rows in
  # the curated categories today and 9 in the corpus, and that grows as
  # CATEGORIES expands.
  #
  # The claims those skip lines carried are not lost: they are asserted by
  # test_generic_implside_rename26 (the impl-side type-parameter rename) and by
  # tgenfunc13's own live skip line (the repeated constraint), both of which run.
  case "$(sed -n 's/^[[:space:]]*\(unit\|program\|library\)[[:space:]].*/\1/p' "$src" | head -1)" in
    unit) gate="unit-source" ;;
  esac

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
  # --retry-skips: attempt the skipped rows instead of trusting the file.
  # A SKIP REASON IS A DATED CLAIM, not a property of the compiler. Entries are
  # written when a row is first triaged and nothing re-reads them, so an entry
  # outlives the gap it describes -- one reason line in pxx.skip says so in its
  # own text ("all are fixed, and unskipping shows `object constructor init` is
  # what is left"). Burning down a skip list has no instrument without this.
  #
  # Retried rows are counted SEPARATELY and the label changes, because the
  # normal pass/fail counters are the conformance verdict and a retry run is not
  # one: it deliberately attempts rows the suite has agreed not to judge, so its
  # failures are expected and its passes are the finding. Mixing them would let
  # a retry run be quoted as "347 pass" or as a regression, and neither is true.
  retrying=0
  if [ -n "$reason" ]; then
    if [ "${RETRY_SKIPS:-0}" = "1" ]; then
      retrying=1
      retried=$((retried+1))
    else
      skip=$((skip+1))
      emit skip "$name" "$reason"
      echo "SKIP $name — $reason"
      continue
    fi
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

  # ---- --diag-map capture ------------------------------------------------
  # WHY THE DIAGNOSTIC AND NOT THE EXIT CODE. --retry-skips can only see a row
  # that started PASSING. A row whose VERDICT is still correct -- it genuinely
  # fails -- while its REASON now names the wrong mechanism is invisible to it,
  # by construction. Measured 2026-09-06 (frankS): a full retry sweep of 117
  # rows found ZERO stale reasons, and clustering the same rows by their FIRST
  # DIAGNOSTIC found FIVE reasons naming a mechanism that was not the cause --
  # three tmoperator rows blaming record management operators, which are
  # implemented and work, while all three actually stop at `undefined variable
  # (InitializeArray)`; and two tgeneric rows blaming generics for a construct
  # refused in a plain class with no generics in it. Every one of the five would
  # have misrouted whoever read it, and two already had.
  #
  # A NULL RESULT INHERITS THE APERTURE OF THE INSTRUMENT THAT PRODUCED IT: the
  # retry sweep's zero was a true answer to a different question. The diagnostic
  # is the channel that can observe this class; the exit code cannot.
  #
  # A row whose diagnostic MOVED is a row whose reason is now suspect, whether
  # or not its verdict changed. This captures; tools/skip_diag_diff.py compares.
  if [ -n "$DIAGMAP" ] && [ "${retrying:-0}" = "1" ]; then
    if [ "$compile_ok" != "0" ]; then
      # THE FIRST `error:` LINE, NOT THE FIRST LINE. Later diagnostics are
      # cascade and churn freely; a banner or a warning ahead of the real one
      # would be captured as the mechanism and would move for reasons that are
      # not the mechanism.
      #
      # AND A FAILED COMPILE WITH NO `error:` LINE IS ITS OWN FACT, kept apart
      # from a real diagnostic. frankS had this harness lie exactly here earlier
      # tonight: the fpc side wrote its binaries elsewhere and EVERY row came
      # back rc=127, which read as a measurement. An environment failure and a
      # compiler diagnostic must not share a value, or a broken run diffs as 86
      # moved mechanisms.
      _diag="$(grep -m1 'error:' "$WORK/cc.log" 2>/dev/null \
               | sed -e "s|$WORK/||g" -e "s|$WORK|<work>|g" -e "s|$SUITE/||g" \
               | tr '\t' ' ')"
      if [ -z "$_diag" ]; then
        _first="$(sed -n '/[^ \t]/{p;q;}' "$WORK/cc.log" 2>/dev/null \
                  | sed -e "s|$WORK/||g" -e "s|$WORK|<work>|g" -e "s|$SUITE/||g" \
                  | tr '\t' ' ')"
        _diag="<compile failed with no error: line> ${_first:-<and no output>}"
      fi
    elif grep -q '^ok:' "$WORK/cc.log" 2>/dev/null; then
      # A VALUE, never an absence. An empty field would be indistinguishable
      # from "row not attempted", and those are different facts.
      #
      # AND THE SUCCESS TEST IS THE `ok:` LINE ON STDOUT, NOT THE EXIT CODE
      # (frankS's decision, adopted here because pascal26 prints `ok: <out>
      # [code=... data=... bss=... procs=...]` on every successful compile --
      # compiler.pas writes it on both the normal and the -S path). An exit 0
      # from something that did not compile anything reads as a clean compile
      # and would enter the map as one, which is the same lie the rc=127 run
      # told from the other direction.
      _diag="<compiles clean>"
    else
      _diag="<exit 0 but no 'ok:' line -- this row was not compiled>"
    fi
    printf '%s\t%s\n' "$name" "$_diag" >> "$DIAGMAP"
  fi

  if [ "$expect_fail" = "1" ]; then
    if [ "$compile_ok" != "0" ]; then
      bump_pass; emit pass "$name" ""
    else
      bump_fail "$name(accepted-invalid)"
      emit fail "$name" "accepted-invalid: %FAIL test compiled"
      echo "FAIL $name — %FAIL test compiled (must be rejected)"
    fi
    continue
  fi

  if [ "$compile_ok" != "0" ]; then
    bump_fail "$name(compile)"
    emit fail "$name" "compile error"
    echo "FAIL $name — compile error:"
    sed -n '1,4p' "$WORK/cc.log" | sed 's/^/    /'
    continue
  fi
  [ "$norun" = "1" ] && { bump_pass; emit pass "$name" ""; continue; }

  # ---- run ----
  ( cd "$WORK" && timeout "$TIMEOUT_S" "$bin" ) > "$WORK/out.txt" 2>&1
  rc=$?
  if [ "$rc" != "$want_rc" ]; then
    bump_fail "$name(exit=$rc)"
    emit fail "$name" "runtime: exit code $rc (want $want_rc)"
    echo "FAIL $name — exit code $rc (want $want_rc)"
    sed -n '1,4p' "$WORK/out.txt" | sed 's/^/    /'
    continue
  fi
  bump_pass; emit pass "$name" ""
done

if [ "${RETRY_SKIPS:-0}" = "1" ]; then
  # A DIFFERENT LABEL ON PURPOSE. This run attempted rows the suite has agreed
  # not to judge, so it is not a conformance result and must not be quotable as
  # one -- neither as a pass count nor as a regression.
  echo "test-pascal-conformance-retry: $retried skip-listed row(s) re-attempted -- $stale now EXIT-CLEAN (skip entry may be stale), $stillgap still failing (gap confirmed)"
  [ -n "$stale_list" ] && echo "test-pascal-conformance-retry: EXIT-CLEAN, CONFIRM BEFORE BURNING:$stale_list"
  echo "test-pascal-conformance-retry: EXIT-CLEAN IS NOT CORRECT. This harness compares the EXIT CODE, not the output, so a row"
  echo "test-pascal-conformance-retry: that runs to completion printing WRONG VALUES lands in the list above. Measured 2026-09-05:"
  echo "test-pascal-conformance-retry: 3 of 24 were exactly that (tarray2 printed a PChar as its pointer, tforin24 printed garbage"
  echo "test-pascal-conformance-retry: for an enum name, tclass12a printed double where FPC prints 80-bit Extended) -- and all three"
  echo "test-pascal-conformance-retry: already said so in their own skip reasons. Diff each row against fpc 3.2.2 before burning it."
  echo "test-pascal-conformance-retry: this is NOT the conformance verdict; run without --retry-skips for that."
  exit 0
fi
echo "$LABEL: $pass pass, $fail fail, $skip skip, $auto auto-gated (of $((pass+fail+skip+auto)))"
if [ "$fail" != "0" ]; then
  echo "$LABEL: FAILURES:$failed"
  exit 1
fi
