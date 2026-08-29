#!/bin/sh
# SPDX-License-Identifier: MPL-2.0
#
# expect_same.sh — assert two strings are equal, and SAY SO WHEN THEY ARE NOT.
#
#   tools/expect_same.sh <label> <actual> <expected>
#
# Exit 0 when they match, printing nothing. On mismatch, print a labelled
# unified diff of the two operands and exit 1.
#
# WHY THIS EXISTS
# ---------------
# 2,461 Makefile recipe lines assert with a bare
#
#     test "$$(tools/run_target.sh aarch64 $(TESTTMP)/x)" = "$$($(TESTTMP)/x_x64)"
#
# and `test` PRINTS NOTHING when it fails. It captures both operands, compares
# them, discards both, and exits 1. testmgr's job_reason() records the log TAIL
# — deliberately, and with a good argument: a signature list goes stale
# silently, while what the job printed last is true for every failure shape,
# including ones nobody has met. So a silent assertion hands a faithful
# tail-recorder the two compile summaries that happen to precede it.
#
# For the 480 cross-target assertions those two lines are the SAME program built
# for two targets, with different code sizes. That reads as a codegen
# divergence. It is not one — two targets emitting different amounts of code is
# the null hypothesis. A Track T session read it as a divergence, said so to a
# peer, and had to retract it.
#
#     A silent assertion does not merely fail to explain itself. It makes
#     everything downstream explain something ELSE, confidently.
#
# That is strictly worse than an empty reason, which at least reads as
# "unknown".
#
# WHAT IT DOES NOT DO
# -------------------
# It does not decide whether a job failed, and it must not: that stays
# job_reason()'s log tail. This only ensures the tail is the mismatch.
#
# THE VACUOUS PASS
# ----------------
# Two empty operands compare EQUAL, so `test` passes and so does this — which
# is how a test whose subject silently produced nothing looks from the outside.
# We do not change that verdict (480 call sites is the wrong place to alter
# pass/fail semantics), but we refuse to be silent about it: a warning goes to
# stderr naming the label. A vacuous pass that announces itself is a lead; one
# that does not is the shape of
# `feature-t-audit-tests-that-pass-with-the-implementation-removed`.

if [ $# -ne 3 ]; then
    echo "expect_same.sh: usage: expect_same.sh <label> <actual> <expected>" >&2
    exit 2
fi

label="$1"
actual="$2"
expected="$3"

if [ "$actual" = "$expected" ]; then
    if [ -z "$actual" ]; then
        echo "expect_same: WARNING [$label]: both operands are EMPTY — this" \
             "passes, but a subject that produced nothing looks exactly like" \
             "this. Check that the command under test ran." >&2
    fi
    exit 0
fi

# Temp files rather than process substitution: recipes run under /bin/sh, which
# is dash on Debian and has no <(...).
tmp="${TMPDIR:-/tmp}/expect_same.$$"
mkdir -p "$tmp" 2>/dev/null || { echo "expect_same: cannot create $tmp" >&2; exit 2; }
trap 'rm -rf "$tmp"' EXIT INT TERM

printf '%s\n' "$actual"   > "$tmp/actual"
printf '%s\n' "$expected" > "$tmp/expected"

echo "expect_same: MISMATCH [$label]"
# -u so the reason field carries context, not just the differing bytes. Run
# from INSIDE the temp dir and let the filenames be the labels: diff then
# prints `--- expected` / `+++ actual` with no directory part.
#
# Two reasons, and the second is not cosmetic. `--label` is not portable
# (busybox diff spells it -L), and any fallback chained with `||` would fire on
# every mismatch anyway, because diff exits 1 when files DIFFER -- that is the
# normal path here, not an error. That mistake printed the diff twice.
#
# And the paths must not be absolute: an expected output containing an absolute
# /tmp path is rewritten by testmgr, so a leaked one turns a stable diff into a
# per-run-varying one. Relative names avoid the whole question.
#
# The mtime column is trimmed off the ---/+++ header lines for the same family
# of reason: this text becomes a job's REASON via job_reason()'s log tail, and
# a reason that changes on every run looks like a new failure to anything
# comparing one run's reds against the last. A diff header is the one part of
# the output that carries a clock, so it is the one part removed.
( cd "$tmp" && diff -u expected actual ) | sed -e '1,2s/\t.*$//'
exit 1
