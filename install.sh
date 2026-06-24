#!/usr/bin/env bash
#
# install.sh — friendly one-stop setup for a fresh PXX checkout.
#
# Run this from the repo root after cloning:
#
#     ./install.sh
#
# It will:
#   1. verify the pinned compiler runs (no FPC needed — the stable binary ships
#      in the checkout),
#   2. drop a ready-to-use  ./pxx  wrapper in the project root (pinned compiler +
#      all library roots on the search path), and optionally put `pxx` on PATH,
#   3. optionally fetch & configure external libraries (Synapse networking; ESP32
#      IDF toolchain),
#   4. optionally build the Eliah IDE and link  ./eliah  in the root,
#   5. optionally launch ./demos.sh to build & run example apps.
#
# Everything is opt-in via prompts. Non-interactive runs (no TTY, or --yes) take
# the safe defaults: install the wrapper, skip the heavy optional steps.
#
# Flags:
#   --yes            assume defaults, no prompts (CI-friendly)
#   --no-path        don't offer to symlink pxx onto PATH
#   -h | --help      this help

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

ASSUME_YES=0
OFFER_PATH=1
while [ $# -gt 0 ]; do
  case "$1" in
    --yes) ASSUME_YES=1; shift ;;
    --no-path) OFFER_PATH=0; shift ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

# ask PROMPT DEFAULT  → echoes y/n. DEFAULT is y or n. Honors --yes / no-TTY.
ask() {
  local prompt="$1" def="${2:-n}" ans
  if [ "$ASSUME_YES" = 1 ] || [ ! -t 0 ]; then echo "$def"; return; fi
  read -rp "$prompt [$( [ "$def" = y ] && echo 'Y/n' || echo 'y/N' )] " ans || true
  ans="${ans:-$def}"
  case "$ans" in y|Y) echo y ;; *) echo n ;; esac
}

say()  { printf '\n\033[1m== %s\033[0m\n' "$*"; }
note() { printf '   %s\n' "$*"; }

say "PXX install"

# ---------------------------------------------------------------------------
# 1. Compiler
# ---------------------------------------------------------------------------
PINNED="$ROOT/stable_linux_amd64/default/pinned"
arch="$(uname -m)"
if [ "$arch" != x86_64 ] && [ "$arch" != amd64 ]; then
  note "host arch is '$arch'; the committed stable binary is x86-64."
  note "build a native compiler with:  make bootstrap   (needs FPC)"
fi
if [ ! -e "$PINNED" ]; then
  echo "no pinned compiler at $PINNED" >&2
  echo "run 'make bootstrap && make stabilize && make pin' first." >&2
  exit 1
fi
printf 'program pxxsmoke;\nbegin\nend.\n' > /tmp/pxx_smoke.pas
if "$PINNED" /tmp/pxx_smoke.pas /tmp/pxx_smoke >/dev/null 2>&1; then
  note "pinned compiler OK: $PINNED"
else
  echo "pinned compiler did not run a smoke compile — aborting." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 2. ./pxx wrapper (+ optional PATH)
# ---------------------------------------------------------------------------
say "compiler wrapper"
"$ROOT/tools/install.sh" --bindir "$ROOT" >/dev/null
note "wrote ./pxx  (pinned compiler + library roots; auto-tracks re-pins)"
note "use it from anywhere:  $ROOT/pxx foo.pas foo"

if [ "$OFFER_PATH" = 1 ] && [ "$(ask 'Put pxx on your PATH (~/.local/bin)?' n)" = y ]; then
  "$ROOT/tools/install.sh" >/dev/null
  note "installed ~/.local/bin/pxx (ensure ~/.local/bin is on PATH)"
fi

# ---------------------------------------------------------------------------
# 3. External libraries
# ---------------------------------------------------------------------------
say "external libraries"
if [ "$(ask 'Fetch & configure Synapse (networking: HTTP/FTP/SMTP, blocking clients)?' n)" = y ]; then
  "$ROOT/tools/install_externals.sh" || note "synapse fetch failed (network?) — skipped"
  if [ -d "$ROOT/external/synapse" ]; then
    # Per-library compile profile. Synapse expects an FPC dialect; PXX compiles it
    # with --mimic-fpc and the synapse dir on the search path. Recorded here so the
    # build helpers / demos apply it automatically for synapse units only — never
    # to the user's own program. (When the compiler grows per-dir manifests —
    # feature-dynamic-include-paths-config — this file becomes the native form.)
    cat > "$ROOT/external/synapse/pxxlib.cfg" <<'CFG'
# PXX per-library profile for Synapse (applies under this directory only).
mode=fpc
flags=--mimic-fpc
# build synapse-using code with:  pxx --mimic-fpc -Fu external/synapse your.pas
CFG
    note "synapse ready at external/synapse (compile with: --mimic-fpc -Fu external/synapse)"
  fi
fi
if [ "$(ask 'Install the ESP32 IDF toolchain (bare-metal / xtensa+riscv32 targets)?' n)" = y ]; then
  "$ROOT/tools/install_esp32_target.sh" || note "ESP32 IDF install failed — skipped"
  note "after it finishes:  . \$HOME/esp/esp-idf/export.sh"
fi

# ---------------------------------------------------------------------------
# 4. Eliah IDE
# ---------------------------------------------------------------------------
say "Eliah IDE (GTK3)"
if [ "$(ask 'Build the Eliah IDE (needs GTK3 dev libs)?' n)" = y ]; then
  if "$ROOT/apps/ide/build.sh"; then
    ln -sf apps/ide/eliah/eliah "$ROOT/eliah"
    note "built — launch with  ./eliah"
  else
    note "Eliah build failed (GTK3 missing?). Install GTK3 dev libs and retry apps/ide/build.sh"
  fi
fi

# ---------------------------------------------------------------------------
# 5. Demos
# ---------------------------------------------------------------------------
say "done"
note "compiler:  ./pxx"
[ -L "$ROOT/eliah" ] && note "ide:       ./eliah"
note "demos:     ./demos.sh"
echo
if [ "$(ask 'Explore the example apps now (./demos.sh)?' y)" = y ]; then
  exec "$ROOT/demos.sh"
fi
