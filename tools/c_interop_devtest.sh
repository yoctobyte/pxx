#!/bin/sh
set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PXX_STABLE=${PXX_STABLE:-"$ROOT/stable_linux_amd64/default/pinned"}

say() {
  printf '%s\n' "$*"
}

try_compile() {
  label=$1
  shift
  log="/tmp/pxx_${label}.log"
  out="/tmp/pxx_${label}"
  if "$PXX_STABLE" "$@" "$out" >"$log" 2>&1; then
    say "OK    $label"
    if [ -x "$out" ]; then "$out" >/tmp/pxx_${label}.out 2>&1 || true; fi
  else
    say "GAP   $label -- $(tail -1 "$log")"
  fi
}

if [ ! -x "$PXX_STABLE" ]; then
  say "missing pinned stable compiler: $PXX_STABLE"
  exit 1
fi

say "=== C interop devtest against $PXX_STABLE ==="
try_compile crtl_header_smoke -I"$ROOT/lib/crtl/include" "$ROOT/test/crtl_header_smoke.c"
try_compile tiny_regex_re -I"$ROOT/lib/crtl/include" -I"$ROOT/library_candidates/tiny-regex-c" "$ROOT/test/crtl_tiny_regex_match.c"
try_compile tiny_regex_header -I"$ROOT/lib/crtl/include" -I"$ROOT/library_candidates/tiny-regex-c" "$ROOT/test/crtl_tiny_regex_header_smoke.c"
try_compile freebsd_regex_header -I"$ROOT/lib/crtl/include" -I"$ROOT/library_candidates/freebsd-regex/include" "$ROOT/test/crtl_freebsd_regex_header_smoke.c"
try_compile freebsd_regex_regerror -I"$ROOT/lib/crtl/include" -I"$ROOT/library_candidates/freebsd-regex/include" -I"$ROOT/library_candidates/freebsd-regex" "$ROOT/library_candidates/freebsd-regex/regerror.c"
try_compile crtl_src_probe -I"$ROOT/lib/crtl/include" "$ROOT/test/crtl_src_probe.c"
say "(devtest is a dashboard; GAP lines are compiler/library tickets, not a gate)"
