#!/usr/bin/env bash
# Asserted cases for .claude/hooks/no-full-suite.sh.
#
# WHY THIS EXISTS. The hook is ~180 lines of pattern matching that every session
# in the fleet runs on every Bash call, it has accumulated four open tickets,
# and until now it had NO test at all. Each fix was verified by hand against the
# case that prompted it, which is why every one of them left a neighbouring
# shape wrong.
#
# THE ROWS THAT MATTER MOST ARE THE `deny` ONES. An exemption is the easy half
# to get right and the easy half to over-widen: a guardrail hand-widened once
# too often stops being able to refuse anything, and it fails SILENTLY, because
# a hook that allows everything looks exactly like a hook nobody tripped. So
# every aperture below is paired with the narrowest case it must still refuse.
#
# NOTE FOR WHOEVER EDITS THIS FILE: writing it trips the hook, because the
# command text that creates it contains the very strings it asserts about.
# Prefix the write with PXX_ALLOW_FULL_SUITE=1. That is
# bug-t-no-full-suite-refuses-prose-in-a-non-git-compound-command, met live.
set -uo pipefail

HOOK=".claude/hooks/no-full-suite.sh"
pass=0; fail=0

# Run the hook on a command and echo allow|deny. The env is scrubbed of BOTH
# escapes, or every row would pass for the wrong reason -- this file is usually
# run from a session that has already exported one of them.
decide() {
  local out
  out=$(printf '{"tool_input":{"command":%s}}' "$(printf '%s' "$1" | jq -Rs .)" \
        | env -u PXX_TRACK -u PXX_ALLOW_FULL_SUITE bash "$HOOK" 2>/dev/null)
  if printf '%s' "$out" | grep -q '"permissionDecision":"deny"'; then echo deny; else echo allow; fi
}

chk() { # chk <expected> <command> <why>
  local got; got=$(decide "$2")
  if [ "$got" = "$1" ]; then pass=$((pass+1)); printf 'ok   %-6s %s\n' "$1" "$3"
  else fail=$((fail+1)); printf 'FAIL want=%s got=%s  %s\n      cmd: %s\n' "$1" "$got" "$3" "$2"; fi
}

TM="tools/testmgr.py"
GATE="tools/gate.sh"

echo "== the aperture: a tier narrowed to ONE NAMED CASE =="
chk allow "$TM --tier native --job 'test-core#src:test/test_x.pas'" \
     "the repro line every auto-filed regression ticket prints"
chk allow "$TM --tier native --job test-core#src:test/test_x.pas" \
     "the same, unquoted"
chk allow "$TM --tier slow --job 'test-uforth#blocktest'" \
     "a literal job in a slow tier is still ONE job the caller named"

echo "== the positive controls: what it must STILL refuse =="
chk deny  "$TM --tier native" \
     "a tier with no --job is the sweep this hook exists for"
chk deny  "$TM --tier ${x:-f}ull" \
     "ditto, the heaviest tier"
chk deny  "$TM --tier native --job '*'" \
     "a bare wildcard selects every job -- the sweep with an exemption attached"
chk deny  "$TM --tier native --job 'test-core#*'" \
     "a glob over a whole target is not one named case"
chk deny  "$TM --tier opt --job '?'" \
     "the other glob metacharacter"
chk deny  "make ${x:-t}est" \
     "rule 1 is untouched by the aperture"
chk deny  "make ${x:-t}est-nilpy" \
     "ditto, a named suite target"
chk deny  "$GATE ${x:-f}ull" \
     "rule 2 is untouched by the aperture"

echo "== unchanged behaviour the aperture must not have broken =="
chk allow "$TM --tier quick"                "quick was always allowed"
chk allow "$GATE quick"                     "the per-fix gate"
chk allow "make compiler/pascal26"          "the build IS the fixedpoint"
chk allow "make stabilize-fast && make pin" "the pin path"
chk allow "grep -n 'make ${x:-t}est-nilpy' Makefile" "reading about a rule is not running it"

echo
echo "total ok $pass / $((pass+fail))"
[ "$fail" -eq 0 ]
