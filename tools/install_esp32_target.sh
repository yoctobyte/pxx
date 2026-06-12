#!/usr/bin/env sh
# Install or update the ESP32 target toolchain used by PXX's esp32-idf profile.
#
# Defaults:
#   ESP_IDF_DIR=$HOME/esp/esp-idf
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
  sudo apt-get install -y \
    git wget flex bison gperf \
    python3 python3-pip python3-venv \
    cmake ninja-build ccache \
    libffi-dev libssl-dev \
    dfu-util libusb-1.0-0 \
    libgcrypt20 libglib2.0-0 libpixman-1-0 libsdl2-2.0-0 libslirp0 \
    qemu-user qemu-user-static binfmt-support
}

ensure_idf_checkout() {
  parent="$(dirname "$ESP_IDF_DIR")"
  mkdir -p "$parent"

  if [ -d "$ESP_IDF_DIR/.git" ]; then
    say "update: $ESP_IDF_DIR"
    if [ "$ESP_IDF_ALLOW_DIRTY" != 1 ] && [ -n "$(git -C "$ESP_IDF_DIR" status --porcelain)" ]; then
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
  (
    # shellcheck disable=SC1091
    . "$ESP_IDF_DIR/export.sh" >/dev/null
    idf.py --version
    for tool in $ESP_IDF_QEMU_TOOLS; do
      case "$tool" in
        qemu-xtensa)
          if have qemu-system-xtensa; then
            qemu-system-xtensa --version | head -n 1
          else
            say "warn: qemu-system-xtensa not found after export"
          fi
          ;;
        qemu-riscv32)
          if have qemu-system-riscv32; then
            qemu-system-riscv32 --version | head -n 1
          else
            say "warn: qemu-system-riscv32 not found after export"
          fi
          ;;
      esac
    done
  )
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
