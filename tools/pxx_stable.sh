#!/bin/sh
# SPDX-License-Identifier: MPL-2.0
#
# pxx_stable.sh -- print the path of the STABLE compiler: the one Track B,
# the demos and the library suites build with, never the dev compiler.
#
#   tools/pxx_stable.sh                 the compiler's absolute path
#   tools/pxx_stable.sh --target-flag   the flag that compiler needs to emit
#                                       code for THIS host ("" when none)
#
# In a git checkout it is stable_linux_amd64/default/pinned. A RELEASE TARBALL
# has no stable_linux_amd64/; its compilers are compiler/pxx-<arch>, one per
# host, and every script that hard-coded .../pinned died there ("no compiler
# at .../pinned": tools/install.sh, apps/ide/build.sh and test.sh,
# busybox_diff.sh --pinned, make test-fpjson -- measured 2026-09-25 walking the
# beta.1 tarball). This is the one place that knows the fallback.
#
# A pxx-<arch> built by the x86-64 compiler still EMITS x86-64 by default, so
# off x86_64 the fallback needs --target=<arch>; the pinned binary is x86-64
# and needs nothing. Exit 1, with a reason on stderr, when neither exists.
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
PINNED="$ROOT/stable_linux_amd64/default/pinned"

case "$(uname -m)" in
  x86_64|amd64)        hostarch=x86_64 ;;
  aarch64|arm64)       hostarch=aarch64 ;;
  armv7l|armv6l|armhf) hostarch=arm32 ;;
  i386|i486|i586|i686) hostarch=i386 ;;
  *)                   hostarch="" ;;
esac

if [ -e "$PINNED" ]; then
  bin="$PINNED"; flag=""
elif [ -n "$hostarch" ] && [ -x "$ROOT/compiler/pxx-$hostarch" ]; then
  bin="$ROOT/compiler/pxx-$hostarch"
  if [ "$hostarch" = x86_64 ]; then flag=""; else flag="--target=$hostarch"; fi
else
  echo "pxx_stable: no stable compiler: neither $PINNED (a checkout) nor $ROOT/compiler/pxx-${hostarch:-<this arch>} (a release tarball)" >&2
  exit 1
fi

case "${1:-}" in
  "")            printf '%s\n' "$bin" ;;
  --target-flag) printf '%s\n' "$flag" ;;
  *)             echo "pxx_stable: unknown argument $1" >&2; exit 2 ;;
esac
