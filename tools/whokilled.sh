#!/usr/bin/env bash
# whokilled -- what killed a long-running job on this box?
#
# WHY THIS EXISTS
# ---------------
# Two csmith batches died mid-run on 2026-08-20. The ticket recorded: "the
# kernel log is unreadable unprivileged so OOM can be neither confirmed nor
# excluded". That sentence is what cost the investigation: the hypothesis then
# drifted toward OOM for six days on no evidence, because nobody could tell
# whether OOM had been ruled out or merely not looked at.
#
# It was ruled OUT, and one command shows it. `dmesg` is blocked here
# (kernel.dmesg_restrict=1) but `journalctl -k` is NOT if you are in `adm` or
# `systemd-journal` -- and everybody who hit the wall hit it with dmesg.
#
# THE DESIGN RULE, which is the whole point of the script
# -------------------------------------------------------
# **"No evidence of X" and "could not look for X" must never print the same.**
# That conflation is this repo's most expensive recurring defect wearing a new
# hat: a check that reports clean when it could not see. So every probe here
# returns one of three verdicts and says which:
#
#   CLEAR       -- looked, with a source known to be complete: X did not happen
#   FOUND       -- X happened, here is the evidence
#   CANNOT-TELL -- could not read the source; this is NOT clean, and the
#                  script exits 2 so a caller cannot mistake it for clean
#
# ASYMMETRY WORTH KNOWING BEFORE YOU READ THE OUTPUT
# ---------------------------------------------------
# A kernel OOM kill and a systemd-oomd kill both leave a durable record. A
# SIGKILL from another process on this box leaves NONE -- not in the journal,
# not anywhere. So a full CLEAR does not mean "nothing killed it"; it means the
# hypotheses that WOULD have left evidence did not happen, which leaves the one
# that never does. That is a real narrowing and it is the most this evidence can
# support. Do not read CLEAR as "it exited on its own".
#
# Usage:  tools/whokilled.sh [--since "2026-08-20 00:00"] [--until "..."]
#         tools/whokilled.sh --since "2 hours ago"
set -uo pipefail

SINCE="" ; UNTIL=""
while [ $# -gt 0 ]; do
  case "$1" in
    --since) SINCE="${2:-}"; shift 2 ;;
    --until) UNTIL="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,40p' "$0"; exit 0 ;;
    *) echo "whokilled: unknown argument '$1'" >&2; exit 64 ;;
  esac
done

jargs=()
[ -n "$SINCE" ] && jargs+=(--since "$SINCE")
[ -n "$UNTIL" ] && jargs+=(--until "$UNTIL")
window="${SINCE:-boot}${UNTIL:+ .. $UNTIL}"

# OOM lines the kernel emits. Kept together so the two probes below cannot
# drift apart -- a grep that differs between "is it there" and "show me" is
# how you get a CLEAR you cannot reproduce.
OOM_RE='oom-kill|Killed process|Out of memory|oom_reaper|Memory cgroup out of memory'

cannot=0
echo "whokilled: window = $window"
echo

# ---------------------------------------------------------------- kernel OOM
# Completeness matters as much as the result: journalctl -k silently shows a
# non-privileged user nothing rather than erroring, so an empty log and a
# restricted log look identical. A boot's kernel log is thousands of lines; a
# handful means we are being filtered, and that is CANNOT-TELL, not CLEAR.
klines=$(journalctl -k "${jargs[@]}" --no-pager 2>/dev/null | wc -l)
if [ "$klines" -lt 50 ]; then
  echo "  CANNOT-TELL  kernel OOM killer — only $klines kernel lines visible."
  echo "               journalctl -k shows an unprivileged user an EMPTY log, not"
  echo "               an error, so this is indistinguishable from a quiet kernel."
  echo "               Fix: join group 'adm' or 'systemd-journal' (dmesg is blocked"
  echo "               separately by kernel.dmesg_restrict=$(sysctl -n kernel.dmesg_restrict 2>/dev/null || echo '?'))."
  cannot=1
else
  hits=$(journalctl -k "${jargs[@]}" --no-pager 2>/dev/null | grep -ciE "$OOM_RE")
  if [ "$hits" -gt 0 ]; then
    echo "  FOUND        kernel OOM killer — $hits line(s):"
    journalctl -k "${jargs[@]}" --no-pager 2>/dev/null | grep -iE "$OOM_RE" | sed 's/^/                 /' | head -20
  else
    echo "  CLEAR        kernel OOM killer — 0 hits in $klines kernel lines."
  fi
fi

# ------------------------------------------------------------- systemd-oomd
# The one a "no kernel OOM" answer wrongly exonerates. systemd-oomd kills on
# cgroup PSI *before* the kernel is out of memory, logs to its own unit and NOT
# to the kernel log, and it targets the heaviest cgroup -- which on this box is
# exactly a fuzzing batch or a test matrix. Checking only the kernel would have
# produced a confident wrong all-clear.
if ! systemctl list-unit-files systemd-oomd.service >/dev/null 2>&1; then
  echo "  CLEAR        systemd-oomd — not installed on this box."
elif [ "$(systemctl is-active systemd-oomd 2>/dev/null)" != "active" ]; then
  echo "  CLEAR        systemd-oomd — installed but not active."
else
  ohits=$(journalctl -u systemd-oomd "${jargs[@]}" --no-pager 2>/dev/null | grep -ciE 'Killed|Killing')
  olines=$(journalctl -u systemd-oomd "${jargs[@]}" --no-pager 2>/dev/null | wc -l)
  if [ "$ohits" -gt 0 ]; then
    echo "  FOUND        systemd-oomd — $ohits kill line(s):"
    journalctl -u systemd-oomd "${jargs[@]}" --no-pager 2>/dev/null | grep -iE 'Killed|Killing' | sed 's/^/                 /' | head -20
  elif [ "$olines" -eq 0 ] && [ -z "$SINCE" ]; then
    echo "  CANNOT-TELL  systemd-oomd — active, but its journal reads empty."
    cannot=1
  else
    echo "  CLEAR        systemd-oomd — active, 0 kills in $olines unit line(s)."
  fi
fi

# ------------------------------------------------------- cgroup memory.events
# Live counters, not history: they survive the journal being rotated but reset
# when the cgroup goes away, so they answer "is a scope being OOM'd right now"
# and say nothing about last week. Reported separately for that reason.
root=/sys/fs/cgroup/user.slice/user-1000.slice
if [ -r "$root/memory.events" ]; then
  tot=0; worst=""
  while IFS= read -r ev; do
    n=$(awk '/^oom_kill /{print $2}' "$ev" 2>/dev/null); [ -z "$n" ] && continue
    tot=$((tot + n))
    [ "$n" -gt 0 ] && worst="$worst
                 $n  ${ev%/memory.events}"
  done < <(find "$root" -maxdepth 3 -name memory.events 2>/dev/null)
  if [ "$tot" -gt 0 ]; then
    echo "  FOUND        cgroup oom_kill counters — $tot total (LIVE cgroups only):$worst"
  else
    echo "  CLEAR        cgroup oom_kill counters — 0 across live cgroups under user-1000."
    echo "               (Live counters only: a cgroup that already exited took its"
    echo "               count with it, so this cannot speak about a past incident.)"
  fi
else
  echo "  CANNOT-TELL  cgroup memory.events — $root not readable."
  cannot=1
fi

echo
if [ "$cannot" -ne 0 ]; then
  echo "whokilled: INCOMPLETE — at least one probe could not look. Do NOT read"
  echo "           this as an all-clear; resolve the CANNOT-TELL lines first."
  exit 2
fi
echo "whokilled: every probe looked and reported. Remember the asymmetry: OOM"
echo "           leaves a record and a peer's SIGKILL does not, so a full CLEAR"
echo "           narrows the cause to the mechanisms that leave no trace."
exit 0
