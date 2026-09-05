#!/usr/bin/env bash
# One command that runs a lane's gate to completion and prints ONE summary.
#
# Why this exists: an agent that backgrounds `make test-nilpy` and then polls it
# with `sleep 600; tail log` burns a conversation turn per poll and learns
# nothing. Background THIS script instead — it exits when the gate is done, so
# the completion notification IS the result. One task, one answer.
#
#   tools/gate.sh quick     self-host fixedpoint + testmgr quick  (~30s)
#   tools/gate.sh lib       lib-test (Track B/E)
#   tools/gate.sh full      quick + test-nilpy + make test  (only when T is down)
#   tools/gate.sh check     print what would run, and the box's state
#
# Exit status is the gate's: 0 = green. The summary names every step and its
# result, so a failure does not need the logs to be located first. The same
# summary is written to $LOGDIR/summary.log, so a backgrounded run's verdict
# can be read from a FILE rather than from the wrapper's exit status.
set -uo pipefail

MODE="${1:-quick}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

LOGDIR="${TMPDIR:-/tmp}/pxx-gate-$$"
mkdir -p "$LOGDIR"

# THE SUMMARY MUST LAND IN A FILE, NOT ONLY ON STDOUT — otherwise the advice
# this repo gives everywhere ("background the gate and grep the LOG for the
# verdict, because the wrapper reports its own exit status") cannot be followed,
# since the step lines and the verdict existed ONLY in stdout. Measured
# 2026-09-05: a full gate's $LOGDIR held 23 per-step logs and no summary, so the
# tidy PASS block was reachable only through the exact channel the rule says not
# to trust. The per-step logs are still the primary record of WHY a step failed;
# this file is the record of WHAT the verdict was.
SUMMARY="$LOGDIR/summary.log"
: > "$SUMMARY"

# Every line that forms the summary goes through say(): stdout for the caller,
# and $SUMMARY for whoever reads the log afterwards. Deliberately not
# `exec > >(tee ...)` — a tee in a process substitution can lose the FINAL line
# when the script exits, and the final line is the verdict.
say() { printf '%s\n' "$*"; printf '%s\n' "$*" >> "$SUMMARY"; }
PINNED="stable_linux_amd64/default/pinned"

# Track T's watcher runs testmgr on whatever box it lives on, and a full matrix
# run saturates the CPU. A gate that would otherwise take 15 minutes takes 45
# next to one, which reads as "hung" if you do not know it is there. Say so up
# front rather than letting the wait be a mystery.
note_contention() {
  local others load
  # pgrep -c PRINTS 0 and EXITS 1 when nothing matches, so `|| echo 0` appends a
  # second zero and every later `[ "$others" -gt 0 ]` dies with "integer
  # expression expected". Recover on the assignment's status instead.
  others=$(pgrep -fc 'testmgr\.py|twatch\.py' 2>/dev/null) || others=0
  load=$(cut -d' ' -f1 /proc/loadavg 2>/dev/null || echo '?')
  if [ "${others:-0}" -gt 0 ]; then
    say "gate: NOTE Track T tooling is running here ($others process(es)), load $load"
    say "gate:      expect this to take 2-3x longer than on an idle box"
  else
    say "gate: box idle-ish (load $load)"
  fi
}

step() {           # step <name> <logfile> <command...>
  local name="$1" log="$2"; shift 2
  local start end
  start=$(date +%s)
  if "$@" > "$log" 2>&1; then
    end=$(date +%s)
    say "  PASS  $name  ($((end - start))s)"
    return 0
  fi
  end=$(date +%s)
  say "  FAIL  $name  ($((end - start))s)  log: $log"
  tail -n 15 "$log" | sed 's/^/        /'
  return 1
}

fixedpoint() {     # self-host from the PINNED seed — DELEGATED, not re-implemented
  # This used to open-code three rounds and assert A == B == C, where A is built
  # by pinned and B by A. That demands that PINNED ALREADY EMITS WHAT HEAD EMITS,
  # which is false by construction for any change to the compiler's own codegen —
  # add a builtin and B legitimately gains symbols A lacks. So the gate went RED
  # on the normal case, one generation early, and could not go green again until
  # `make pin` ran.
  #
  # It is the exact mistake the Makefile's $(COMPILER) rule documents as wrong
  # (chore-makefile-selfhost-iterate-to-convergence): "a stale seed legitimately
  # needs an extra round ... demanding one pass is what made a normal bootstrap
  # look like a failure." gate.sh reimplemented the check inline and reintroduced
  # the bug it had already been fixed for elsewhere — so the fix is to stop having
  # a second implementation at all.
  #
  # tools/selfhost_fixedpoint.sh is authoritative: it iterates to MAX_ROUNDS and
  # additionally enforces the anti-Thompson property (the hermetic fixedpoint must
  # equal compiler/pascal26), which the inline version never checked. It also
  # PRINTS ITS REASON — the old function sent every round to /dev/null, so a FAIL
  # line sat above a 0-byte fixedpoint.log and named no cause, which is what turned
  # each occurrence into a manual bisect.
  #
  # Exit 77 is its "no pinned stable" skip and must not read as a gate failure.
  tools/selfhost_fixedpoint.sh
  local rc=$?
  if [ "$rc" = 77 ]; then
    echo "SKIP: no pinned stable to seed from — self-host gate not run"
    return 0
  fi
  [ "$rc" = 0 ] || stale_binary_hint
  return "$rc"
}

# The check above is honest — "the binary we test with is not the one these
# sources define" is TRUE when compiler/pascal26 is merely old. But its stated
# causes ("local seed contamination, or a self-perpetuating miscompile") send you
# hunting a miscompile, when on a shared checkout the overwhelmingly common cause
# is that a SIBLING landed a compiler change and nobody rebuilt here yet.
#
# It cost two full gate runs on two consecutive days (2026-08-12, -13) before
# anyone noticed the pattern: the gate's own testmgr step rebuilds the binary as
# a side effect, so the FIRST run after a sibling's commit always fails and the
# re-run always passes, which reads as flakiness rather than staleness.
#
# Deliberately a hint, not a fix: gate.sh must NOT rebuild before comparing, or
# it loses the ability to catch a genuinely contaminated binary — which is the
# entire point of the anti-Thompson check.
stale_binary_hint() {
  local newest binmt
  newest=$(git log -1 --format=%ct -- compiler/ 2>/dev/null) || return 0
  binmt=$(stat -c %Y compiler/pascal26 2>/dev/null) || return 0
  [ -n "$newest" ] && [ -n "$binmt" ] || return 0
  if [ "$binmt" -lt "$newest" ]; then
    say "gate: NOTE compiler/pascal26 is OLDER than the last commit touching"
    say "gate:      compiler/ ($(git log -1 --format='%h %s' -- compiler/ | cut -c1-60))"
    say "gate:      That is a STALE BINARY, not a miscompile — a sibling landed a"
    say "gate:      compiler change and this checkout has not rebuilt."
    say "gate:      Run 'make compiler/pascal26' (~12s) and re-gate."
  fi
}

# The seam between the pinned binary's FROZEN builtin RTL and the repo's LIVE
# lib/rtl. `make pin` copies compiler/builtin/** into
# stable_linux_amd64/default/builtin/, so from that moment the pinned compiler
# builds a frozen builtin set against whatever lib/rtl says TODAY. A Track A
# change that adds a builtin and uses it from lib/rtl is coherent, self-hosts,
# and passes the whole quick gate -- and breaks every $(PXX_STABLE) build the
# instant it lands, because `pinned` still has the pre-change builtin.
#
# That happened on 97b1812fe: `undefined variable (PXXNilRefHook)`, and Tracks
# B, D and E were dead on master until the next pin. It was found by accident,
# by an unrelated scratch compile. Nothing stood in this seam, because both
# halves of `gate.sh quick` build with the FRESHLY BUILT compiler -- the gate
# was not weak here, it was looking somewhere else entirely.
#
# Compile only; running the program is not the point. Any live-RTL/frozen-
# builtin mismatch IS a compile error, which is the entire failure mode.
# ~1s, so it runs in every mode rather than earning its own tier.
#
# Proven failable before landing (a canary that has never been seen to fail is
# not yet a canary): in a scratch copy of the tree, adding one reference to an
# absent builtin in lib/rtl/sysutils.pas reproduces the original error shape
# and exit 1.
# ONE FIXTURE WAS 1/111th OF THE POPULATION, AND THE SEAM MOVED OFF IT.
# The control above is real -- injecting an absent builtin into sysutils.pas
# does reproduce the error and exit 1 -- but injecting a fault into the one
# file a guard reads cannot reveal that it reads only one file. Measured
# 2026-09-05: `a623307bd` deleted the RTL's own TMethod in favour of the new
# System.TMethod builtin, and against pin v403 (`ce63beeeb`, which predates it)
# 20 of 111 lib/rtl units and the whole of lib/pcl fail with
# `unknown type: TMethod` -- json, http, streams, re, subprocess, markdown,
# base64, pathlib, configparser among them, none of which changed. This row
# reported PASS in 1s. sysutils survives for a reason no one could have picked
# on purpose: its only mention of TMethod is `PMethod = ^TMethod`, a forward
# pointer reference, which never forces the type to resolve. The fixture was
# PHYSICALLY UNABLE to observe the seam it was standing in.
#
# So sweep instead of sampling, and discover the list rather than keeping one:
# compile every ROOT unit (one no other lib/rtl unit `uses`), which pulls in
# every unit anything depends on. A unit added tomorrow is either a root or is
# reached from one; nothing here goes stale by a file appearing.
#
# COST, measured as wired and not from the prototype: ~18s on a healthy tree
# (53 roots, -P 8, uncontended) and ~39s when it is failing, against 1s before.
# That is real, on a ~110s quick gate, and it buys the row an aperture instead
# of a sample. Three cheaper shapes were measured and rejected: --emit-obj and
# -O0 save nothing (~440ms/unit either way, and --emit-obj cannot emit a
# program); a greedy set-cover over the roots removes NONE of them, because a
# root appears in no closure but its own; and one program that `uses` all 53 at
# once (5.5s, and it would need no attribution on the healthy path) fails
# unconditionally today on the two mimic_* units below, so it would fall
# through to the sweep every run and cost strictly more.
pinned_rtl_canary() {
  local pin=stable_linux_amd64/default/pinned
  local pinabs; pinabs=$(readlink -f "$pin" 2>/dev/null)
  local work="$LOGDIR/pinned-rtl"
  local roots="$work/roots.txt" fails="$work/fails.txt"
  [ -x "$pin" ] || { say "gate: (no pinned binary at $pin)"; return 0; }
  [ -d lib/rtl ] || {
    echo "^^ lib/rtl is not there at all. That is a broken tree, not a"
    echo "   configuration, and it must not read as the same verdict as"
    echo "   'no pinned binary'."
    return 1
  }
  mkdir -p "$work"

  LC_ALL=C ls lib/rtl/*.pas | sed 's|.*/||; s|\.pas$||' | LC_ALL=C sort > "$work/all.txt"
  for f in lib/rtl/*.pas; do
    sed -n '/^ *uses/I,/;/p' "$f" | tr 'A-Z' 'a-z' | tr ',' '\n' |
      sed 's/uses//; s/;//; s/[^a-z0-9_]//g' | grep -v '^$'
  done | LC_ALL=C sort -u > "$work/used.txt"
  LC_ALL=C comm -23 "$work/all.txt" "$work/used.txt" > "$roots"

  # A sweep that discovered nothing passes every unit it never compiled, and
  # says PASS in less time than before -- which reads as the tree being fine.
  # 54 roots today; 20 is far below any real tree and far above a `uses`
  # parser that has broken. Assert it, and BRANCH on it.
  local n; n=$(wc -l < "$roots")
  if [ "$n" -lt 20 ]; then
    echo "^^ the pinned-RTL sweep discovered only $n root units (expected >= 20)."
    echo "   This is the DISCOVERY breaking, not lib/rtl shrinking. A sweep with"
    echo "   no inputs cannot fail, and it reports PASS on all 111 units."
    return 1
  fi

  # Positive control, and it is about THIS invocation, not about the tree: a
  # probe naming a type no compiler has must be REJECTED. If it compiles, the
  # command below is not reaching a compiler and every unit passes vacuously.
  printf 'program probe;\nvar x: __pxx_gate_absent_type;\nbegin end.\n' > "$work/control.pas"
  if "$pinabs" "$work/control.pas" "$work/control.bin" >/dev/null 2>&1; then
    echo "^^ the canary's own control COMPILED a program naming a type that does"
    echo "   not exist. The invocation is not compiling anything, so the sweep"
    echo "   below would report PASS without building a single unit."
    return 1
  fi

  # The probe must NOT be named after the unit it tests: a file called
  # `strutils.pas` is read AS the unit strutils (`expected 'unit' before
  # 'program'`) and shadows the real one on the search path. All 54 rows
  # failed identically that way while this was being written.
  # --threadsafe so the units that genuinely require it (palthread*, cthreads)
  # compile in the mode they are really built in, rather than being excluded --
  # an exclusion list is the part that silently stops covering anything.
  cat > "$work/one.sh" <<'ONE'
#!/bin/sh
u=$1; work=$2; pin=$3
printf 'program probe;\nuses %s;\nbegin end.\n' "$u" > "$work/probe_$u.pas"
out=$("$pin" --threadsafe -Fulib/rtl "$work/probe_$u.pas" "$work/probe_$u.bin" 2>&1) ||
  echo "$u :: $(echo "$out" | grep -m1 -i error | cut -c1-100)"
ONE
  chmod +x "$work/one.sh"
  xargs -P 8 -I{} "$work/one.sh" {} "$work" "$pinabs" < "$roots" |
    LC_ALL=C sort > "$fails"

  # A unit that fails under BOTH compilers is not this seam and never was: it
  # is ordinary breakage, or a unit no Pascal program can `uses` standalone at
  # all. Two are exactly that today -- mimic_string and mimic_urllib_request
  # reach NilPy frontend builtins (`pyvar_is_objtag`) and fail identically
  # against a compiler built from this very tree. Absolute failure would pin
  # this row RED forever, after a pin fixes the thing it is watching, and a
  # gate that cannot pass is not a gate. So ask the question the row actually
  # means: does the PIN fail where HEAD succeeds. That needs no exclusion list
  # (the part that rots), it costs nothing on a healthy tree because only
  # already-failing units are retried, and it sorts the two classes for
  # whoever reads the log instead of merging them.
  if [ -s "$fails" ]; then
    local seam="$work/seam.txt" both="$work/both.txt"
    : > "$seam"; : > "$both"
    while IFS= read -r line; do
      local u="${line%% ::*}"
      if [ -x compiler/pascal26 ] &&
         ./compiler/pascal26 --threadsafe -Fulib/rtl \
             "$work/probe_$u.pas" "$work/head_$u.bin" >/dev/null 2>&1; then
        echo "$line" >> "$seam"
      elif [ -x compiler/pascal26 ]; then
        echo "$line" >> "$both"
      else
        # No freshly built compiler to compare against: cannot tell the two
        # apart, so report every failure as the seam rather than none.
        echo "$line" >> "$seam"
      fi
    done < "$fails"

    if [ -s "$both" ]; then
      echo "note: $(wc -l < "$both") unit(s) fail under the PIN and under compiler/pascal26 alike."
      sed 's/^/     /' "$both"
      echo "   Not the frozen-builtin seam: a compiler built at this tree fails on"
      echo "   them too (not always the same error). Owner is whoever owns that"
      echo "   unit, not this row."
    fi

    if [ -s "$seam" ]; then
      echo "^^ the PINNED binary cannot COMPILE $(wc -l < "$seam") of $n root units that a"
      echo "   compiler built from THIS TREE compiles cleanly:"
      sed 's/^/     /' "$seam"
      echo "   An 'unknown type' or 'undefined variable' naming a lib/rtl unit means"
      echo "   a commit added a builtin and used it from lib/rtl without a pin:"
      echo "   coherent, self-hosts, and breaks every \$(PXX_STABLE) build until"
      echo "   someone pins. The change is usually RIGHT and the remedy is a pin,"
      echo "   not a revert."
      return 1
    fi
  fi

  # ...and then RUN one. Near-zero, and it is a different question: the compile
  # answers "does the frozen builtin still satisfy lib/rtl's references", the
  # run answers "does the result work". A pinned RTL that compiles and then
  # dies is just as broken for Track B, and nothing else in the dev loop asks.
  # Reported apart from the compile so triage stays sharp -- a failure here is
  # NOT the frozen-builtin seam.
  local src=test/test_uses_sysutils.pas
  if [ ! -f "$src" ]; then
    echo "^^ the canary's run fixture $src is gone. It is TRACKED, so absence is"
    echo "   a broken tree, not a configuration -- see the SKIP note below."
    return 1
  fi
  "$pinabs" "$src" "$work/run.bin" >/dev/null 2>&1 || {
    echo "^^ the pinned binary failed on the run fixture $src itself."
    return 1
  }
  "$work/run.bin" >/dev/null 2>&1 || {
    echo "^^ the pinned binary COMPILED lib/rtl but the result did not run."
    echo "   That is not the frozen-builtin seam; it is an ordinary runtime"
    echo "   fault in the pinned RTL. Same impact on Track B, different owner."
    return 1
  }
}

say "gate: mode=$MODE  logs=$LOGDIR"
note_contention

if [ "$MODE" = check ]; then
  say "gate: would run:"
  case "${2:-quick}" in *) :;; esac
  echo "  quick -> self-host fixedpoint (pinned seed) | testmgr --tier quick   (~30s)"
  echo "  lib   -> make lib-test"
  echo "  full  -> quick + make test-nilpy + make test   (only when Track T is down)"
  # `{ cmd || echo ...; } | sed`, NOT `cmd | sed ... || echo ...`. The second
  # form was here and could never fire: `||` reads the PIPELINE's status, which
  # is sed's, and sed exits 0 on empty input -- so a missing or failing
  # twatch.py printed NOTHING where a status block belongs, and the fallback
  # that exists for exactly that case was unreachable for its whole life.
  # Measured: with the command exiting 3, the old form captured "" and the new
  # one captures the message; a succeeding command still passes through
  # unchanged (both arms asserted). One of three instances of this shape found
  # in one night across three agents -- `!`, `&&`/`||`, a pipe and `2>/dev/null`
  # each replace the exit status you asked for, and none of them says so.
  { tools/twatch.py --status 2>/dev/null || echo "(twatch status unavailable)"; } | sed 's/^/  /'
  # --status answers "is anyone covering the repo"; `trackt health` answers
  # "is the watcher on THIS box trustworthy right now", incl. alive-but-wedged.
  echo "  (watcher health on this box: tools/trackt.py health)"
  exit 0
fi

RC=0

# Before the case, so it covers quick, lib and full alike from ONE place. The
# three-branch version of this was the first draft; a check that has to be
# remembered in each new mode is the check that will be missing from the next
# one.
if [ -x stable_linux_amd64/default/pinned ] && [ -f test/test_uses_sysutils.pas ]
then
  step "pinned builds live lib/rtl" "$LOGDIR/pinned-rtl-canary.log" \
       pinned_rtl_canary                                              || RC=1
else
  say "  SKIP  pinned builds live lib/rtl (no pinned binary or fixture)"
fi

# Literal short-jump displacements. CheckRel8 already guards the OVERFLOW class
# and hard-errors; this is the other one -- a hand-counted displacement over a
# span someone else emits, which stays in range when that span changes size and
# lands mid-instruction. It assembles, links, runs and corrupts a value, and no
# symbol, relocation or size number moves. Two were found shipping on 2026-09-02
# (WriteLn(s:w) on a ShortString truncated; LoadFile into a ShortString always
# returned empty), which is why this is a gate row and not a ticket.
#
# Under a second: a text scan, before the case so no mode can forget it. It runs
# --selftest first because a check that cannot fail prints PASS -- the selftest
# asserts it REJECTS both shapes it was built from and ACCEPTS a fixed-size one.
# A SKIP ON A TRACKED FILE IS A GREEN GATE WITH NO GATE IN IT. Seven arms below
# guarded a checker with `[ -f ]` or `[ -x ]` and printed SKIP when it was not
# there, setting no RC -- so a tree missing every checker in tools/ passed. All
# seven files are tracked at mode 100755: absence is a BROKEN TREE, not a
# configuration, and the two must not produce the same verdict.
#
# The `-x` three were worse than the `-f` four, because the mode bit is the part
# that goes missing without the file doing so: a `cp`, a tarball restore, an
# archive export, a filesystem that does not carry the bit. The checker sits
# right there, readable, and the gate reports SKIP. Those now test `-f` and
# invoke through the interpreter, so the bit is not load-bearing at all.
#
# The genuinely conditional SKIPs are left alone and are a different animal:
# `fpc not installed` (a host tool nobody commits), `no pinned binary`, `no
# origin ref`, `compiler/ unchanged`. Those say NOT APPLICABLE. These said
# NOT PRESENT and were read as the same thing.
# Reported by frankuser on the census arm; the other six are the same shape.
if [ -f tools/rel8_literal_span_check.py ]; then
  step "rel8 literal-jump spans" "$LOGDIR/rel8-literal-span.log" \
       python3 tools/rel8_literal_span_check.py --selftest .        || RC=1
else
  say "  FAIL  rel8 literal-jump spans — tools/rel8_literal_span_check.py is MISSING"
  echo "        It is TRACKED (mode 100755), so its absence is a broken tree, not a"
  echo "        configuration. A gate arm that skips on a committed file passes green"
  echo "        for a tree that has no checker in it at all."
  RC=1
fi

# THE SEED CANARY. Same placement argument as the block above: before the case,
# so no mode can forget it.
#
# `make compiler/pascal26` compiles compiler.pas WITH PXX. So the per-fix loop --
# and the byte-identical self-host fixedpoint with it, our strongest signal --
# is blind BY CONSTRUCTION to breakage that only FPC sees, because the only
# compiler it ever consults is the one under test. pxx resolves names across the
# whole unit; FPC resolves in source order. A call placed above its declaration
# with no `forward;` therefore self-hosts green and makes `compiler.pas`
# uncompilable by FPC -- which is the path a fresh checkout with NO trusted
# binary must take to exist at all.
#
# Twice in two days, in two unrelated frontends (WasmDataAddr 2026-08-28,
# RExprRecId 2026-08-29), every gate green both times.
#
# tools/forwardlint.py already existed for this and exits 1 correctly. NOTHING
# INVOKED IT -- so it caught both and told no one. A trigger nobody is assigned
# to watch is not a trigger; that, not the missing check, was the defect.
#
# Costs ~5.5s: it reads the include stream, it does not build anything. (Was
# documented as ~1s until 2026-08-30 -- stale by 5x, and it was the figure three
# decide tickets inherited and argued the cost from. Measured three runs on
# plexus: 5.71 / 5.48 / 5.23. It grows with the include stream, so re-measure
# rather than trusting this line.)
if [ -f tools/forwardlint.py ] && [ -f compiler/compiler.pas ]; then
  step "fpc seed compiles (forward decls)" "$LOGDIR/forwardlint.log" \
       python3 tools/forwardlint.py                                   || RC=1
else
  say "  FAIL  fpc seed compiles — tools/forwardlint.py or compiler/compiler.pas is MISSING"
  echo "        Both are TRACKED, so this is a broken tree rather than a configuration."
  RC=1
fi

# THE ABI-ORACLE CHECK. Wired for the reason the forwardlint block above gives:
# a trigger nobody is assigned to watch is not a trigger. abi.inc's PREVIOUS
# enforcement was a review grep -- something a human had to remember to run and
# then read -- and it never fired once in its life, because it was calibrated to
# the spelling `IsRef or` rather than to the shape. It ended up matching exactly
# one line in the tree: a COMMENT quoting the rule. So the check was not merely
# dead, it had become actively reassuring.
#
# Runs in well under a second (a regex pass over 7 files; it builds nothing).
#
# It carries a BASELINE of known, filed disagreements rather than suppressing
# them, and it FAILS if a baseline entry matches nothing -- so the file cannot
# outlive its cause the way the grep did. --selftest holds 12 asserted controls.
# bug-a-the-abi-oracle-invariant-is-enforced-by-a-grep-that-cannot-fire
if [ -f tools/abi_oracle_lint.py ]; then
  step "backends ask the ABI oracle" "$LOGDIR/abi-oracle-lint.log" \
       python3 tools/abi_oracle_lint.py                              || RC=1
else
  say "  FAIL  backends ask the ABI oracle — tools/abi_oracle_lint.py is MISSING"
  echo "        It is TRACKED (mode 100755), so its absence is a broken tree, not a"
  echo "        configuration. A gate arm that skips on a committed file passes green"
  echo "        for a tree that has no checker in it at all."
  RC=1
fi

# IR OP NAME COVERAGE. IROpName's one load-bearing caller is the "unsupported
# node in IR codegen" error every backend raises, so an op it does not name
# reports itself as `unknown` on EVERY target and the only way to find out which
# op is missing is to edit the backend and self-compile. Seven of 75 were
# unnamed until 2026-08-31; IR_CLASSREF was found that expensive way, on xtensa.
#
# The gap could open because nothing counted -- the count that found it was a
# parser run once by hand. This is that parser, wired, so the eighth cannot open
# silently. Sub-second; it parses two files and builds nothing.
# bug-a-iropname-has-no-entry-for-seven-ir-ops-so-a-missing-arm-reports-unknown
if [ -f tools/iropname_lint.py ]; then
  step "IROpName names every IR op" "$LOGDIR/iropname-lint.log" \
       python3 tools/iropname_lint.py                                 || RC=1
else
  say "  FAIL  IROpName names every IR op — tools/iropname_lint.py is MISSING"
  echo "        It is TRACKED (mode 100755), so its absence is a broken tree, not a"
  echo "        configuration. A gate arm that skips on a committed file passes green"
  echo "        for a tree that has no checker in it at all."
  RC=1
fi

# crtl NAME MAP STALENESS. compiler/crtl_names.inc is GENERATED from the crtl
# headers, and a C program's call to a crtl function resolves through it -- so a
# stale map is a function that exists in lib/crtl and cannot be reached from C.
# Adding a crtl function is a two-file change and only one of them is obvious.
#
# It is wired here because it only ran in `lib-test`, which the per-fix loop does
# not run: the map went stale on 2026-09-02 and was auto-filed EIGHT times as
# regression-lib-test-crtl-reachability{,-2..-8} before anyone held one. Track T
# catches it within ~8 commits by design; that is the right cadence for a
# breadth sweep and the wrong one for a generated file whose regenerator is one
# command. 0.44s measured -- it parses headers and builds nothing.
#
# NOT crtl_reachability.py, which is the sibling check in the same lib-test job:
# that one is 9.5s, a fifth of this whole gate, and it answers a different
# question (is every declared function reachable from its OWN header). Wiring
# the cheap half is the whole point; wiring both would make the gate the thing
# people skip.
# regression-lib-test-crtl-reachability-8
if [ -f tools/gen_crtl_map.py ]; then
  step "crtl name map is not stale" "$LOGDIR/crtl-map.log" \
       python3 tools/gen_crtl_map.py --check                          || RC=1
else
  say "  FAIL  crtl name map is not stale — tools/gen_crtl_map.py is MISSING"
  echo "        It is TRACKED, so its absence is a broken tree rather than a"
  echo "        configuration, and skipping would pass green for a tree with no"
  echo "        checker in it."
  RC=1
fi

# AST SLOT-WRITE CENSUS. ASTLeft/ASTRight are children for most kinds and a
# PAYLOAD for a few, so a generic walker that recurses on them corrupts memory
# for exactly the overloading kinds -- the census declares which is which and
# snapshots every write, so a new one is REVIEWED rather than discovered.
#
# It is wired here because it only ran in `test-core`, which the per-fix loop
# does not run: d49de34b6 added two legitimate child writes, left the snapshot
# stale, and shipped test-core RED with `make compiler/pascal26` and
# `gate.sh quick` both green. A review gate that fires only where nobody looks
# reviews nothing. --self-check is its positive control (an injected payload
# write into a slot the table calls a child must be flagged); ~5s, builds
# nothing. A RED here on your own change usually means `--update` after reading
# the diff, which is what its message says.
if [ -f tools/ast_slot_overloads.py ]; then
  step "AST slot-write census matches its snapshot" "$LOGDIR/ast-slot-census.log" \
       python3 tools/ast_slot_overloads.py --self-check                        || RC=1
else
  say "  FAIL  AST slot-write census — tools/ast_slot_overloads.py is MISSING"
  echo "        It is TRACKED (mode 100755), so its absence is a broken tree, not a"
  echo "        configuration. A gate arm that skips on a committed file passes green"
  echo "        for a tree that has no checker in it at all."
  RC=1
fi

# EVERY MAKEFILE ASSERTION CAN FAIL, AND CAN SAY WHY. ~3900 recipe lines
# already assert through tools/expect_same.sh; a bare `test "$(a)" = "$(b)"`
# prints NOTHING on mismatch, so testmgr's log-tail reason records the two
# preceding compile summaries instead and reads as a codegen divergence. Six
# stragglers are converted alongside this guard -- a conversion on its own is a
# one-time cleanup, and this makes it a property of the file. It also refuses
# an assertion whose exit status is discarded by a following `;`, the worse
# sibling: that one cannot fail at all.
# bug-t-a-silent-test-assertion-makes-the-harness-report-the-wrong-thing
if [ -f tools/silent_assertion_check.py ]; then
  step "every Makefile assertion can fail and can say why" "$LOGDIR/silent-assertion.log" \
       python3 tools/silent_assertion_check.py                                 || RC=1
else
  say "  FAIL  Makefile assertion check — tools/silent_assertion_check.py is MISSING"
  echo "        It is TRACKED (mode 100755), so its absence is a broken tree, not a"
  echo "        configuration. A gate arm that skips on a committed file passes green"
  echo "        for a tree that has no checker in it at all."
  RC=1
fi

# EVERY DEVTEST CASE A HARNESS DEFINES IS ALSO RUN BY IT. A Track T devtest
# defines `t_*` functions and runs them from a hand-maintained list -- either
# `TESTS = (...)` at module level or the same tuple inline in main(). Nothing
# connects the two, so a case can be defined, imported, syntactically perfect
# and never executed. Measured 2026-09-05: four such cases in
# silent_assertion_check_devtest.py. Nothing errored; the harness printed OK
# with a guard count that had not moved, which is the only tell and is
# invisible unless you remembered yesterday's number. Sub-second, pure AST.
if [ -f tools/devtest_case_registration.py ]; then
  step "every devtest case defined is a devtest case run" "$LOGDIR/devtest-registration.log" \
       python3 tools/devtest_case_registration.py                              || RC=1
else
  say "  FAIL  devtest case registration — tools/devtest_case_registration.py is MISSING"
  echo "        It is TRACKED (mode 100755), so its absence is a broken tree, not a"
  echo "        configuration. A gate arm that skips on a committed file passes green"
  echo "        for a tree that has no checker in it at all."
  RC=1
fi

# THE FULL-SUITE HOOK'S OWN CASES. That hook runs on EVERY Bash call in every
# session in the fleet and had no test at all until 2026-09-03, which is how it
# reached four open tickets: each fix was checked by hand against the case that
# prompted it, so each one left a neighbouring shape wrong. The rows that earn
# this its place are the `deny` ones -- an over-widened guardrail fails SILENTLY,
# because a hook that allows everything looks exactly like a hook nobody
# tripped. Sub-second; it runs no suite, it only feeds the hook payloads.
# bug-t-the-full-suite-hook-keys-on-the-tier-name-so-it-refuses-every-auto-filed-repro
if [ -f tools/test_no_full_suite_hook.sh ]; then
  step "the full-suite hook still refuses a sweep" "$LOGDIR/no-full-suite-hook.log" \
       sh tools/test_no_full_suite_hook.sh                               || RC=1
else
  say "  FAIL  the full-suite hook still refuses a sweep — tools/test_no_full_suite_hook.sh is MISSING"
  echo "        It is TRACKED (mode 100755), so its absence is a broken tree, not a"
  echo "        configuration. A gate arm that skips on a committed file passes green"
  echo "        for a tree that has no checker in it at all."
  RC=1
fi

# THE UNWIRED-TEST CANARY. Same placement argument as the two blocks above --
# before the case, so no mode can forget it -- and the same failure it fixes as
# the forwardlint block: the checker already existed, already exited 1, and was
# invoked by nothing anyone reads in time.
#
# tools/check_test_wiring.py runs in limited+full as part of tools-devtest,
# which is right for the CENSUS (47 unwired files today, most in deferred lanes,
# expensive to act on) and useless for the author: frankwasm wrote nine tests on
# 2026-08-30, the checker named all nine and exited 1 all day, and one of them
# was a campaign's ACCEPTANCE test -- the fcl-json line the campaign existed for,
# quoted to three agents -- executed by nothing but its author's hand.
#
# This asks the cheap half instead: did THIS push add a file under test/ that no
# rule references? Scoped to origin/$BRANCH..HEAD, so it names what you just
# wrote and nobody inherits a backlog. The agent who wrote the file still has
# the oracle in their head; a sweep three weeks later has to reconstruct it.
#
# ~0.7s (measured three runs on plexus: 0.70 / 0.66 / 1.29, ~2-4% of quick's
# ~30s budget). Re-measure rather than trusting this line -- it scans the
# Makefile and tools/, so it grows with both.
#
# SKIPs loudly without an origin ref rather than passing: a check that reports
# success by not running is the exact defect check_test_wiring.py exists to
# remove, and `--since` returns 2 rather than 0 when it cannot scope.
GATE_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo master)
if [ -f tools/check_test_wiring.py ] \
   && git rev-parse --verify -q "origin/$GATE_BRANCH" >/dev/null 2>&1; then
  step "this push wires the tests it adds" "$LOGDIR/test-wiring.log" \
       python3 tools/check_test_wiring.py --since "origin/$GATE_BRANCH" || RC=1
else
  say "  SKIP  this push wires the tests it adds (no origin/$GATE_BRANCH ref)"
fi

# A frozen-string operand kind fed to a width-aware normaliser must come from
# IRStrTkOf/IRFrozenKindOfAddr, never IntToTypeKind(IRTk[...]) -- the latter
# reads the IR's generic tyString tag, which means an 8-byte prefix, so under
# -dPXX_SHORTSTRING the site reads eight bytes of [len][chars] as a length.
# It fails FALSE rather than loudly: the length mismatch short-circuits before
# any character is compared, so nothing crashes and nothing prints garbage.
#
# Three normalisers already carried a COMMENT saying this and arm32 violated
# its own comment at four sites (fixed 764dc3a30 / 64f230d12). Prose telling
# the next author what not to do is not a mechanism preventing it, and this is
# a call-site PATTERN rather than a semantic judgement, so it can be checked.
# ~0.1s; carries its own positive control AND a negative control, and refuses
# (exit 2) if a fenced normaliser has been renamed away under it.
if [ -f tools/check_frozen_kind_resolution.py ]; then
  step "frozen kind via IRStrTkOf, not IntToTypeKind" "$LOGDIR/frozen-kind.log" \
       python3 tools/check_frozen_kind_resolution.py                  || RC=1
fi

# The .inc files with TWO including configurations: compiler.pas, and a
# standalone oracle harness that MOCKS the defs.inc environment. A new reference
# from one of these into defs.inc compiles in the compiler and breaks the
# harness, and NEITHER per-fix gate can see it -- the fixedpoint proves the
# compiler reproduces ITSELF, not that a file it reads is still readable by
# anything else. Twice in eleven days, different symbols each time
# (InlineAsmLineHoleN 2026-08-21, DwBackHits 2026-09-01, the second caught by
# seven 7 commits after it landed).
#
# CONDITIONAL, in the same shape as the FPC seed canary: it costs ~6s and only
# a diff touching one of these files can cause the defect, so a gate that ran it
# unconditionally would be paying it on every fix to catch a class reachable
# from seven files. Both the uncommitted diff and the unpushed range are checked
# -- CLAUDE.md's rule that quick's canary only fires on an UNCOMMITTED tree is a
# footgun worth not copying.
INC_TWO_CONFIGS='compiler/asmtext.*\.inc|compiler/x64enc\.inc|compiler/rv32enc\.inc|compiler/rel8\.inc'
inc_harness_touched() {
  git diff --name-only HEAD 2>/dev/null | grep -qE "$INC_TWO_CONFIGS" && return 0
  if git rev-parse --verify -q "origin/$GATE_BRANCH" >/dev/null 2>&1; then
    git diff --name-only "origin/$GATE_BRANCH..HEAD" 2>/dev/null       | grep -qE "$INC_TWO_CONFIGS" && return 0
  fi
  return 1
}
if [ -x tools/standalone_inc_harnesses.sh ] && inc_harness_touched; then
  step "standalone .inc harnesses compile" "$LOGDIR/inc-harness.log" \
       tools/standalone_inc_harnesses.sh || RC=1
fi

case "$MODE" in
  quick|full)
    # QUICK = the native confirm CLAUDE.md actually prescribes: testmgr --tier
    # quick + self-host byte-identical, ~30s. It used to also run
    # `make test-nilpy`, which spent 625 of its 649 seconds in one suite -- a
    # full gate wearing the fast gate's name, in the mode agents are told to
    # reach for BETWEEN EDITS. Two 554s runs in one session, both green, both
    # finding nothing, is what filed this.
    #
    # Dropping it is safe now in a way it was not before:
    #   - `testmgr --tier quick` carries dense NilPy and C canaries as of
    #     feature-t-quick-canary-for-nilpy-and-c, so a gross NilPy break is
    #     still caught here, in ~1s;
    #   - the whole test-nilpy suite is enrolled in Track T's limited/full
    #     matrix, so it IS run -- offloaded, which is the entire point;
    #   - ten minutes is also long enough to overlap another build, which is
    #     the window bug-t-selfhost-build-uses-fixed-tmp-paths-colliding and
    #     feature-t-snapshot-compiler-binary-per-run are about.
    # FPC seed canary, started FIRST and in the BACKGROUND so it overlaps the
    # steps below instead of adding to them. Four separate "Identifier not
    # found" breaks landed on master in three days (PyMakeTruthy, PyBytesCi,
    # PyWiden, EmitAsmX64) — every one a routine called from an include that
    # sits EARLIER in compiler.pas than the file defining it. pxx's own
    # frontend resolves all of them; FPC is single-pass and does not, so the
    # property is invisible to every other check a dev runs, and the watcher
    # only reports it hours later.
    #
    # It is affordable precisely because it is concurrent: the seed build takes
    # ~11s against this gate's ~14-30s, so wall time is max() rather than sum()
    # and the gate stays the thing you run between edits. Skipped when compiler
    # sources are untouched (nothing else can break the seed) and when FPC is
    # absent, which must be a SKIP and never a failure — the watcher boxes are
    # not required to have it.
    #
    # ARMED AGAINST THE MERGE-BASE, not against HEAD. `git diff HEAD` only sees
    # an UNCOMMITTED change, and the loop this gate belongs to is edit -> gate
    # -> commit -> push OR edit -> commit -> gate -> push. In the second order
    # the canary skipped precisely when it mattered: the change is finished, it
    # is about to be pushed, and the tree is clean, so the check that exists to
    # catch it reported "no uncommitted compiler/ changes" and stood down. That
    # is the hole this canary was added to close, reopened one step later.
    # The merge-base is the right question — "what have I changed that origin
    # has not seen", covering committed-but-unpushed — and it deliberately does
    # NOT arm for a sibling's compiler commit that I merely have not pulled:
    # their push already ran this, and arming on it would fire on nearly every
    # gate in a repo this busy.
    #
    # SECOND ARMING RULE, added 2026-08-29. The paragraph above is right that a
    # sibling's pushed compiler commit should not be re-gated on every run, but
    # it justified that with "their push already ran this" -- and the gate is
    # deliberately OPTIONAL per fix (CLAUDE.md). So "already on origin" means
    # nobody objected, not proven green, and the gap is not theoretical: a
    # duplicate forward in rparser.inc sat broken on master for hours while
    # clean trees printed PASS, then surfaced inside an unrelated Track A gate
    # naming Track R's file. Invisible where it landed, misattributed where it
    # showed up.
    #
    # So the canary also arms when origin/master's compiler/ has moved past the
    # last sha THIS CLONE actually proved. The state file is untracked and
    # per-clone on purpose: "seed-green" is a property of a box that ran fpc,
    # not of a commit, and tracking it would let one box's green silence every
    # other box. Cost stays one seed build per origin/master advance -- still
    # concurrent, still ~11s -- and a repo sitting still still pays nothing.
    seed_pid=
    seed_base=$(git merge-base origin/master HEAD 2>/dev/null) || seed_base=HEAD
    seed_green_file="$(git rev-parse --git-dir 2>/dev/null)/pxx-seed-green"
    seed_green=$(cat "$seed_green_file" 2>/dev/null || true)
    seed_arm=no
    seed_mine=no          # is there a local compiler/ change that could be the cause?
    if ! git diff --quiet "$seed_base" -- compiler/ 2>/dev/null; then
      seed_arm=yes; seed_mine=yes
    elif [ -z "$seed_green" ] || ! git cat-file -e "$seed_green^{commit}" 2>/dev/null; then
      seed_arm=yes       # nothing proved on this clone yet
    elif ! git diff --quiet "$seed_green" HEAD -- compiler/ 2>/dev/null; then
      seed_arm=yes       # pulled compiler/ commits this clone has never seeded
    fi
    if command -v fpc >/dev/null 2>&1 && [ "$seed_arm" = yes ]; then
      ( rm -rf "$LOGDIR/seed_u" && mkdir -p "$LOGDIR/seed_u" && \
        fpc -Mobjfpc -O2 -Tlinux -Px86_64 -FU"$LOGDIR/seed_u" \
            -FE"$LOGDIR/seed_u" -o"$LOGDIR/seed26" compiler/compiler.pas \
        ) >"$LOGDIR/fpc-seed.log" 2>&1 &
      seed_pid=$!
    fi

    # Under a second, and it is the ONLY layer that survives `git add -f`.
    # .gitignore is advisory and the fetchers' own guards only cover the roots
    # they know about; this one derives the roots from the fetchers, so a new
    # fetcher cannot quietly escape it. Cheap enough for the per-fix gate, which
    # is the point — a check that only runs nightly cannot stop a push.
    step "no vendor tracked" "$LOGDIR/no-vendor.log" \
         tools/check_no_vendor_tracked.sh                                || RC=1

    # Under a second, same reason as the vendor check above: a stated invariant
    # that only a nightly notices cannot stop a push. CLAUDE.md scopes
    # per-backend optimisation to x86-64 + aarch64, and for most of the -O3
    # campaign nothing checked whether that scope was being MET -- it drifted to
    # 22 : 6 while the prose said both were in scope, because "aarch64 is in
    # scope" and "aarch64 got 6 of 22" are consistent statements. This does not
    # forbid a one-armed slice; it forbids one nobody noticed was one-armed, by
    # making the widened delta an edit in the same commit.
    # feature-opt-o3-w1-operand-folds-are-x86-64-only-aarch64-has-four-of-fifteen
    step "-O3 backend parity" "$LOGDIR/o3-parity.log" \
         tools/check_o3_backend_parity.py                                || RC=1

    step "self-host fixedpoint" "$LOGDIR/fixedpoint.log" fixedpoint      || RC=1
    step "testmgr --tier quick" "$LOGDIR/quick.log" \
         tools/testmgr.py --tier quick                                   || RC=1

    if [ -n "$seed_pid" ]; then
      if wait "$seed_pid"; then
        say "  PASS  FPC seed canary (concurrent)"
        # Record only when the tree's compiler/ IS the commit -- with local
        # edits in flight, what we just proved is not any sha, and stamping
        # HEAD would suppress the next run for a state never built.
        if git diff --quiet HEAD -- compiler/ 2>/dev/null; then
          git rev-parse HEAD > "$seed_green_file" 2>/dev/null || true
        fi
      else
        say "  FAIL  FPC seed canary (concurrent)  $LOGDIR/fpc-seed.log"
        # The error is thousands of lines above the tail — FPC keeps warning
        # after the error that stopped it — so surface it rather than the tail.
        grep -E "Error:|Fatal:" "$LOGDIR/fpc-seed.log" | head -5 | sed 's/^/        /'
        # Say WHOSE break it is before saying what it might be. When there is
        # no local compiler/ change, the answer is not "what did I do" and an
        # agent reading a failure inside its own gate will assume it is.
        if [ "$seed_mine" = yes ]; then
          echo "        this tree has local compiler/ changes — likely yours"
        else
          echo "        NOT YOUR CHANGE: no local compiler/ edits — this break is"
          echo "        already on origin/master. Do not bisect your own work."
        fi
        echo "        two shapes both fail only under FPC (pxx accepts both):"
        echo "          - MISSING forward: a routine called from an include EARLIER"
        echo "            in compiler.pas than the one defining it — add a forward,"
        echo "            see bug-a-fpc-seed-drift-emitasmx64-forward"
        echo "          - DUPLICATE forward: the same routine forwarded twice in one"
        echo "            file — delete the later one, see"
        echo "            bug-r-a-duplicate-forward-in-rparser-breaks-the-fpc-seed-build"
        RC=1
      fi
    elif command -v fpc >/dev/null 2>&1; then
      say "  SKIP  FPC seed canary (compiler/ unchanged, and seeded green at ${seed_green:0:12})"
    else
      say "  SKIP  FPC seed canary (fpc not installed)"
    fi
    if [ "$MODE" = full ]; then
      step "make test-nilpy"    "$LOGDIR/test-nilpy.log" make test-nilpy || RC=1
      step "make test"          "$LOGDIR/test.log" make test             || RC=1
    fi
    ;;
  lib)
    step "make lib-test"        "$LOGDIR/lib-test.log" make lib-test     || RC=1
    ;;
  *)
    # FALL THROUGH to the verdict line rather than exiting here. This arm used to
    # `exit 2` directly, which made it the one path that returned a nonzero status
    # WITHOUT publishing it — the exact failure the comment below exists to
    # prevent, exempted by an early exit. It is also the cheapest RED available,
    # so it doubles as the positive control that a RED verdict reaches the log.
    say "gate: unknown mode '$MODE' (quick | lib | full | check)"
    RC=2
    ;;
esac

# PUBLISH THE STATUS IN THE LINE, not only in $?. gate.sh has been reported as
# "printed RED and exited 0" three times by three different lanes — and each
# time the tool was correct and the CALLER lost the status to a trailing
# command: `| tail`, `; echo "exit=$?"`, `&& cp`, a cleanup line. That is not a
# shell gotcha anyone outgrows; it is the general rule ("trust the exit code")
# having a domain where it is exactly backwards, so the well-trained reflex
# fires wrong.
#
# gate.sh cannot fix its caller's shell. What it CAN do is stop being the
# ambiguous half: printing the code it is about to return puts the verdict and
# the status in the same line, so a wrapper reporting 0 over `gate: RED (exit
# 1)` is visibly the wrapper's error rather than a suspected bug in here. Same
# property as the seed canary naming the sha it stands on — publish the evidence
# you rely on, so a reader can check the claim instead of trusting it.
if [ "$RC" = 0 ]; then say "gate: GREEN (exit 0)"; else say "gate: RED (exit $RC)"; fi
exit "$RC"
