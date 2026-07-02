#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Compatibility wrapper. The shell implementation at rebase time is kept as
# tools/progress.sh.reference; the fast implementation lives in progress.py.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec python3 "$ROOT/tools/progress.py" "$@"
