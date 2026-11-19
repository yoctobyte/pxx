#!/bin/sh
# stable_runs.sh <compiler-path> <hint>
#
# Precondition for a recipe that EXECUTES the pinned stable compiler. `test -x`
# is not that check: the executable bit is a property of the file, not of
# whether this CPU can run it. On `via` (aarch64), where the repo ships only
# stable_linux_amd64, every `test -x $(PXX_STABLE)` guard passed, and the one
# message a reader got said "No pinned stable at <path>" about a path where one
# demonstrably was. So: say which of the two different problems this is.
#   missing / not executable -> the old message plus <hint>
#   present but will not run -> name its architecture and this host's
# bug-a-test-x-on-the-pinned-stable-passes-on-a-foreign-architecture
p="$1"
hint="$2"
if [ ! -x "$p" ]; then
  echo "No pinned stable at $p. $hint"
  exit 1
fi
if ! "$p" --version >/dev/null 2>&1; then
  what=$(file -b "$p" 2>/dev/null | cut -d, -f1-2)
  echo "The pinned stable at $p exists but does not run on this host ($(uname -m)): ${what:-unknown format}."
  echo "This is an architecture mismatch, not a missing compiler. Build a native seed (make bootstrap needs FPC) or run under an emulator."
  exit 1
fi
exit 0
