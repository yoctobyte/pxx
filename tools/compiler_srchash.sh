#!/usr/bin/env bash
# Print one hash over EVERY source the self-host fixedpoint is a fixedpoint of.
#
# WHY A SCRIPT AND NOT A MAKE EXPRESSION. The expression has to name 210 files,
# and a recipe that inlines $(COMPILER_SRC) $(COMPILER_INC) is echoed verbatim
# by `make -n` -- three times over, ~45KB, into the dry-run output that
# testmgr's make_dry_run() parses and that every agent reads. The Makefile
# already carries a note about exactly this trap ("it would print a
# $(COMPILER_INC) expansion that runs to 200 file names").
#
# THE COST OF THE SCRIPT IS A SECOND STATEMENT OF THE FILE SET, and that is the
# defect this whole change is about. It is DECLARED, and
# tools/selfhost_stamp_devtest.sh asserts the two lists are identical in both
# directions -- a file the Makefile compiles and this misses, or the reverse,
# fails there. One declared duplicate with a check is a different animal from
# an undeclared copy that nothing compares.
#
# The hash is per-file sha256 hashed as a SET (sorted), so it covers file NAMES
# as well as contents -- adding or deleting an .inc changes it -- and does not
# depend on the order a glob expands.
# bug-a-the-mandatory-fixedpoint-step-reports-success-from-a-stale-stamp
set -uo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" || exit 1

if [ "${1:-}" = "--list" ]; then
  # the devtest's half of the contract: print the set, one per line, sorted
  printf '%s\n' compiler/compiler.pas compiler/*.inc compiler/builtin/*.pas \
                lib/rtl/*.pas lib/asmcore/*.pas | sort
  exit 0
fi

"$0" --list | tr '\n' '\0' | xargs -0 sha256sum | sort | sha256sum | cut -d' ' -f1
