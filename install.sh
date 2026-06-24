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
COMPILER="$PINNED"          # what ./pxx will point at
SMOKE='program pxxsmoke; begin end.'
printf '%s\n' "$SMOKE" > /tmp/pxx_smoke.pas

runs_here() { [ -e "$1" ] && "$1" /tmp/pxx_smoke.pas /tmp/pxx_smoke >/dev/null 2>&1; }

if runs_here "$PINNED"; then
  note "stable compiler OK: $PINNED"
else
  # The committed stable binary is x86-64; on another host arch it can't run.
  # Native per-arch binaries are not distributed yet
  # (see docs/progress/backlog/feature-native-arch-binaries). Build one from
  # source if the toolchain is here, otherwise guide the user.
  note "the committed stable binary doesn't run on this host ($(uname -m))."
  if command -v fpc >/dev/null 2>&1 && command -v make >/dev/null 2>&1; then
    if [ "$(ask 'Build a native compiler from source now (make bootstrap, needs FPC)?' y)" = y ]; then
      ( cd "$ROOT" && make bootstrap ) || { echo "make bootstrap failed — aborting." >&2; exit 1; }
      if runs_here "$ROOT/compiler/pascal26"; then
        COMPILER="$ROOT/compiler/pascal26"
        note "native compiler built: $COMPILER"
      else
        echo "built compiler did not run a smoke — aborting." >&2; exit 1
      fi
    else
      echo "skipped. Build later with:  make bootstrap" >&2; exit 1
    fi
  else
    echo "no runnable compiler and FPC/make not found." >&2
    echo "install FPC ('sudo apt install fpc') then:  make bootstrap" >&2
    exit 1
  fi
fi

# ---------------------------------------------------------------------------
# 2. ./pxx wrapper (+ optional PATH)
# ---------------------------------------------------------------------------
say "compiler wrapper"
"$ROOT/tools/install.sh" --bindir "$ROOT" --compiler "$COMPILER" >/dev/null
note "wrote ./pxx  (compiler + library roots on the unit search path)"
note "use it from anywhere:  $ROOT/pxx foo.pas foo"

if [ "$OFFER_PATH" = 1 ] && [ "$(ask 'Put pxx on your PATH (~/.local/bin)?' n)" = y ]; then
  "$ROOT/tools/install.sh" --compiler "$COMPILER" >/dev/null
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
