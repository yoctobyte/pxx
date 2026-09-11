#!/bin/sh
# SPDX-License-Identifier: MPL-2.0
# file_ticket_clobber_devtest.sh — positive controls for file-ticket.sh's refusal to
# overwrite a ticket that already exists on master.
#
# Runs the REAL script end to end against a throwaway bare repo standing in for
# origin, so nothing here can reach the live remote. Three rows, and the first one
# is the control that matters: a guard which blocks legitimate filing would pass a
# test that only checks the refusal.
#
#   1. a NEW slug            -> must SUCCEED and land      (guard must not over-block)
#   2. an EXISTING slug      -> must REFUSE, rc=3, origin UNCHANGED
#   3. an EXISTING slug + --replace -> must SUCCEED, content replaced, and the
#                              commit subject must SAY so (a bland subject is the
#                              defect this guard exists to prevent)
set -eu

SCRIPT=$(cd "$(dirname "$0")" && pwd)/file-ticket.sh
[ -f "$SCRIPT" ] || { echo "devtest: file-ticket.sh not found beside me" >&2; exit 1; }

W=$(mktemp -d)
cleanup() { rm -rf "$W"; }
trap cleanup EXIT INT TERM

G="git -c user.email=devtest@example.invalid -c user.name=devtest -c commit.gpgsign=false"

# --- origin (bare) + a clone with one ticket already filed --------------------
$G init -q --bare "$W/origin.git"
$G clone -q "$W/origin.git" "$W/wc" 2>/dev/null  # "empty repository" warning is expected
cd "$W/wc"
$G symbolic-ref HEAD refs/heads/master
mkdir -p devdocs/progress/backlog-core tools
cp "$SCRIPT" tools/file-ticket.sh
chmod +x tools/file-ticket.sh
printf 'ORIGINAL BODY — frankH diagnosis, must not vanish\n' \
  > devdocs/progress/backlog-core/bug-a-existing.md
$G add -A
$G commit -q -m "seed"
$G push -q origin master
$G branch -q --set-upstream-to=origin/master master 2>/dev/null || true

fail=0
note() { printf '  %s\n' "$1"; }

# --- row 1: a NEW slug must land (the over-blocking control) -------------------
mkdir -p "$W/in/devdocs/progress/backlog-core"
printf 'a brand new ticket\n' > "$W/in/devdocs/progress/backlog-core/bug-a-brand-new.md"
if sh tools/file-ticket.sh "$W/in/devdocs/progress/backlog-core/bug-a-brand-new.md" >"$W/r1.log" 2>&1; then
  if $G -C "$W/origin.git" cat-file -e master:devdocs/progress/backlog-core/bug-a-brand-new.md 2>/dev/null; then
    note "row1 PASS  new slug landed"
  else
    note "row1 FAIL  exited 0 but the file is not on origin"; fail=1
  fi
else
  note "row1 FAIL  refused a NEW slug (rc=$?) — the guard over-blocks"; cat "$W/r1.log"; fail=1
fi

# --- row 2: an EXISTING slug must be refused, origin untouched -----------------
before=$($G -C "$W/origin.git" rev-parse master)
printf 'MY WORSE VERSION — would have clobbered frankH\n' \
  > "$W/in/devdocs/progress/backlog-core/bug-a-existing.md"
set +e
sh tools/file-ticket.sh "$W/in/devdocs/progress/backlog-core/bug-a-existing.md" >"$W/r2.log" 2>&1
rc=$?
set -e
after=$($G -C "$W/origin.git" rev-parse master)
body=$($G -C "$W/origin.git" show master:devdocs/progress/backlog-core/bug-a-existing.md)
if [ "$rc" -eq 3 ] && [ "$before" = "$after" ] && [ "$body" = "ORIGINAL BODY — frankH diagnosis, must not vanish" ]; then
  note "row2 PASS  refused (rc=3), origin unmoved, original body intact"
else
  note "row2 FAIL  rc=$rc before=$before after=$after"; sed 's/^/       /' "$W/r2.log"; fail=1
fi

# --- row 3: --replace must work AND must not be bland -------------------------
set +e
sh tools/file-ticket.sh --replace "$W/in/devdocs/progress/backlog-core/bug-a-existing.md" >"$W/r3.log" 2>&1
rc=$?
set -e
body=$($G -C "$W/origin.git" show master:devdocs/progress/backlog-core/bug-a-existing.md 2>/dev/null || echo MISSING)
subj=$($G -C "$W/origin.git" log -1 --format=%s master)
if [ "$rc" -eq 0 ] && [ "$body" = "MY WORSE VERSION — would have clobbered frankH" ]; then
  case "$subj" in
    *REPLACE*) note "row3 PASS  replaced, and the subject says so: $subj" ;;
    *) note "row3 FAIL  replaced under a bland subject: $subj"; fail=1 ;;
  esac
else
  note "row3 FAIL  rc=$rc body=$body"; sed 's/^/       /' "$W/r3.log"; fail=1
fi

[ "$fail" -eq 0 ] && { echo "file_ticket_clobber_devtest: OK (3 rows)"; exit 0; }
echo "file_ticket_clobber_devtest: FAILED" >&2; exit 1
