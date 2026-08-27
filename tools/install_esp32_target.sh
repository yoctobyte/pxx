#!/usr/bin/env sh
# SPDX-License-Identifier: MPL-2.0
# Install or update the ESP32 target toolchain used by PXX's esp32-idf profile.
#
# Defaults:
#   ESP_IDF_DIR=$HOME/esp/esp-idf
#
# no-vendor-tracked: out-of-scope — this clones esp-idf to $ESP_IDF_DIR (default
# $HOME/esp/esp-idf), OUTSIDE the repo, so it cannot put third-party source under
# a tracked path. Declared explicitly rather than inferred: tools/check_no_vendor_tracked.sh
# derives its protected roots from the fetchers and treats an undeclared one as a
# failure, so that adding a fetcher forces this decision instead of silently
# widening the hole. NOTE the build OUTPUT does land in-tree, at
# examples/esp32/*/build/ — gitignored, and checked separately by that script,
# because a 9.1MB libwpa_supplicant.a from there is already in this repo history.
#   ESP_IDF_VERSION=v6.0.1
#   ESP_IDF_TARGETS=esp32s2,esp32s3
#   ESP_IDF_QEMU_TOOLS="qemu-xtensa qemu-riscv32"
#
# A child script cannot permanently update the caller's PATH. After this
# succeeds, run:
#   . "$ESP_IDF_DIR/export.sh"
set -eu

ESP_IDF_DIR="${ESP_IDF_DIR:-$HOME/esp/esp-idf}"
ESP_IDF_VERSION="${ESP_IDF_VERSION:-v6.0.1}"
ESP_IDF_TARGETS="${ESP_IDF_TARGETS:-esp32s2,esp32s3}"
ESP_IDF_QEMU_TOOLS="${ESP_IDF_QEMU_TOOLS:-qemu-xtensa qemu-riscv32}"
ESP_IDF_REPO="${ESP_IDF_REPO:-https://github.com/espressif/esp-idf.git}"
ESP_IDF_INSTALL_HOST_PACKAGES="${ESP_IDF_INSTALL_HOST_PACKAGES:-auto}"
ESP_IDF_ALLOW_DIRTY="${ESP_IDF_ALLOW_DIRTY:-0}"

say() {
  printf '%s\n' "$*"
}

have() {
  command -v "$1" >/dev/null 2>&1
}

apt_has_candidate() {
  # True when apt can actually install this name on this release. `apt-cache
  # policy` prints `Candidate: (none)` for a name that exists only as a
  # transitional/renamed stub, which is exactly the case worth catching.
  [ -n "$(apt-cache policy "$1" 2>/dev/null | awk '/Candidate:/ && $2 != "(none)" {print $2}')" ]
}

install_host_packages() {
  case "$ESP_IDF_INSTALL_HOST_PACKAGES" in
    0|no|false|skip)
      say "skip: host package install disabled"
      return
      ;;
    auto|1|yes|true)
      ;;
    *)
      say "error: ESP_IDF_INSTALL_HOST_PACKAGES must be auto/yes/no" >&2
      exit 2
      ;;
  esac

  if ! have apt-get; then
    say "skip: apt-get not found; install ESP-IDF prerequisites manually"
    return
  fi

  say "install: Debian/Ubuntu host packages"
  # apt-get update fails hard when ANY configured repo is broken (e.g. a stale
  # third-party PPA), which has nothing to do with the packages below. Warn
  # and continue; the install step still fails loudly if packages are missing.
  if ! sudo apt-get update; then
    say "warn: apt-get update failed (likely an unrelated broken repo); continuing"
  fi
  # Resolve each name against what this release actually ships before asking
  # for it. Ubuntu's 64-bit-time_t transition renamed a pile of runtime
  # libraries to a `t64` suffix, so on 24.04+ `libglib2.0-0` has NO candidate
  # (`libglib2.0-0t64` is the package) -- and with `set -e` one such name makes
  # `apt-get install` exit non-zero and takes the whole ESP-IDF install with it,
  # before a single byte is cloned. Measured on plexus 2026-08-27: libglib2.0-0
  # unavailable, libglib2.0-0t64 already installed.
  #
  # So: keep a name that has a candidate, else try `<name>t64`, else drop it and
  # SAY SO. Dropping is right for this list -- it is host prerequisites, and
  # ESP-IDF's own install.sh fails loudly later if something is genuinely
  # missing -- but a silent drop would turn a packaging change into a mystery
  # build error, which is what the `warn:` line is for.
  pkgs=''
  missing=''
  for pkg in \
    git wget flex bison gperf \
    python3 python3-pip python3-venv \
    cmake ninja-build ccache \
    libffi-dev libssl-dev \
    dfu-util libusb-1.0-0 \
    libgcrypt20 libglib2.0-0 libpixman-1-0 libsdl2-2.0-0 libslirp0 \
    qemu-user qemu-user-static binfmt-support
  do
    if apt_has_candidate "$pkg"; then
      pkgs="$pkgs $pkg"
    elif apt_has_candidate "${pkg}t64"; then
      say "note: $pkg -> ${pkg}t64 (time_t transition)"
      pkgs="$pkgs ${pkg}t64"
    else
      missing="$missing $pkg"
    fi
  done
  [ -n "$missing" ] && say "warn: no candidate for:$missing (skipped)"
  # shellcheck disable=SC2086
  sudo apt-get install -y $pkgs
}

ensure_idf_checkout() {
  parent="$(dirname "$ESP_IDF_DIR")"
  mkdir -p "$parent"

  if [ -d "$ESP_IDF_DIR/.git" ]; then
    say "update: $ESP_IDF_DIR"
    # --untracked-files=no: the guard exists to protect LOCAL EDITS from being
    # clobbered by the checkout/submodule-update below, and neither of those
    # touches an untracked file. Counting untracked ones made the script
    # non-idempotent after its OWN first run: it clones the default branch and
    # then checks out $ESP_IDF_VERSION, which leaves behind submodule
    # directories that exist on master and not on the tag (measured on plexus
    # 2026-08-27 after a clean v6.0.1 install: components/bt/controller/
    # lib_esp32h4, lib_esp32s31, esp_ble_audio). Re-running then refused with
    # "checkout has local changes" and told the user to set ALLOW_DIRTY, for
    # files nobody wrote.
    if [ "$ESP_IDF_ALLOW_DIRTY" != 1 ] && [ -n "$(git -C "$ESP_IDF_DIR" status --porcelain --untracked-files=no)" ]; then
      say "error: ESP-IDF checkout has local changes: $ESP_IDF_DIR" >&2
      say "set ESP_IDF_ALLOW_DIRTY=1 to continue anyway" >&2
      exit 1
    fi
    git -C "$ESP_IDF_DIR" fetch --tags origin
  elif [ -e "$ESP_IDF_DIR" ]; then
    say "error: ESP_IDF_DIR exists but is not a Git checkout: $ESP_IDF_DIR" >&2
    exit 1
  else
    say "clone: $ESP_IDF_REPO -> $ESP_IDF_DIR"
    git clone --recursive "$ESP_IDF_REPO" "$ESP_IDF_DIR"
  fi

  say "checkout: $ESP_IDF_VERSION"
  git -C "$ESP_IDF_DIR" checkout "$ESP_IDF_VERSION"
  git -C "$ESP_IDF_DIR" submodule update --init --recursive
}

install_idf_tools() {
  say "install: ESP-IDF tools for $ESP_IDF_TARGETS"
  (
    cd "$ESP_IDF_DIR"
    ./install.sh "$ESP_IDF_TARGETS"
  )

  if [ -n "$ESP_IDF_QEMU_TOOLS" ]; then
    say "install: Espressif QEMU tools: $ESP_IDF_QEMU_TOOLS"
    IDF_PATH="$ESP_IDF_DIR" python3 "$ESP_IDF_DIR/tools/idf_tools.py" install $ESP_IDF_QEMU_TOOLS
  fi
}

validate_install() {
  say "validate: ESP-IDF environment"
  # THROUGH BASH, deliberately. ESP-IDF's export.sh is a bash/zsh script: it
  # locates IDF_PATH from $BASH_SOURCE, and under dash it prints "Could not
  # automatically detect IDF_PATH" and returns having exported nothing. This
  # script is #!/usr/bin/env sh, so `set -e` then reported the WHOLE install as
  # failed after it had in fact succeeded completely -- measured on plexus
  # 2026-08-27, exit code 1 with IDF v6.0.1 and both qemu forks correctly in
  # place. Exporting IDF_PATH first does NOT help; export.sh re-derives it and
  # bails the same way. Upstream supports bash/zsh/fish here and nothing else,
  # so asking for bash is the fix rather than a workaround.
  bash -c '
    set -eu
    . "$1/export.sh" >/dev/null
    idf.py --version
    for tool in $2; do
      case "$tool" in
        qemu-xtensa)
          if command -v qemu-system-xtensa >/dev/null 2>&1; then
            qemu-system-xtensa --version | head -n 1
          else
            echo "warn: qemu-system-xtensa not found after export"
          fi
          ;;
        qemu-riscv32)
          if command -v qemu-system-riscv32 >/dev/null 2>&1; then
            qemu-system-riscv32 --version | head -n 1
          else
            echo "warn: qemu-system-riscv32 not found after export"
          fi
          ;;
      esac
    done
  ' _ "$ESP_IDF_DIR" "$ESP_IDF_QEMU_TOOLS"
}

main() {
  say "ESP_IDF_DIR=$ESP_IDF_DIR"
  say "ESP_IDF_VERSION=$ESP_IDF_VERSION"
  say "ESP_IDF_TARGETS=$ESP_IDF_TARGETS"
  say "ESP_IDF_QEMU_TOOLS=$ESP_IDF_QEMU_TOOLS"
  say

  install_host_packages
  ensure_idf_checkout
  install_idf_tools
  validate_install

  say
  say "done"
  say "To use ESP-IDF in this shell, run:"
  say "  . \"$ESP_IDF_DIR/export.sh\""
}

main "$@"
