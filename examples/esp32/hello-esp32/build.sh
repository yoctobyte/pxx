#!/usr/bin/env bash
# SPDX-License-Identifier: 0BSD
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
PXX="${PXX:-$("$ROOT/tools/pxx_stable.sh")}"  # the pin in a checkout, compiler/pxx-<arch> in a release

cd "$(dirname "$0")"

rm -f main/main.o main/libpxx_app.a
# The CHIP NAME, not --target=xtensa: the generic spelling answers the S3's
# memory map and instruction set, and this is an LX6. The chip name also
# implies the windowed ABI on the IDF platform.
# ESP_PXXFLAGS / ESP_EXTRA_COMPONENT_DIRS / ESP_REQUIRES: the per-project extra
# libraries espide's Settings > Libraries writes into espide.cfg beside this
# script. Unset for a plain command-line build, which is why every use is
# ${..:-}. This is the worked example for the convention; a project that wants
# extra -Fu roots or IDF components reads the same three.
#
# Verified 2026-09-27, one variable at a time, each with the other unset and a
# nothing-set negative control, because a variable that is silently IGNORED
# also builds green:
#   nothing set   rc=0  driver in main's REQUIRES: no   extra component: no
#   ESP_REQUIRES  rc=0  driver in main's REQUIRES: YES  extra component: no
#   ..COMPONENT_  rc=0  driver in main's REQUIRES: no   extra component: YES,
#                       and COMPILED (build/esp-idf/<name>/lib<name>.a). Not
#                       the linked symbol: nothing references it and IDF links
#                       plain archives, so the linker correctly drops it and a
#                       symbol row would read "no" for a mechanism that works.
# Read off build/project_description.json's build_component_info, which is the
# resolved graph and not an echo of the variable.
#
# EXTRA_COMPONENT_DIRS WANTS A FOLDER OF COMPONENTS, NOT OF PROJECTS. IDF reads
# every subdirectory of it as a component, so a folder of IDF projects (this
# repo's own examples/esp32, say) makes it read each project's CMakeLists as a
# component and cmake dies inside __component_get_requirements with
# `define_property command is not scriptable` -- a message that names neither
# the folder nor the project. That cost a build here; it is a bad value, not a
# defect in the wiring above.
"$PXX" --target=esp32 ${ESP_PXXFLAGS:-} main/main.pas main/main.o
xtensa-esp32-elf-ar rcs main/libpxx_app.a main/main.o

idf.py set-target esp32
IDF_ARGS=()
# `if`, not `[ ... ] && ...`: under `set -e` a trailing && list whose test
# FAILS is a failing command, so the plain build -- the one with no extra
# component dirs, i.e. every command-line build -- would have exited 1 right
# here. The short form is the one everybody writes and it is wrong in exactly
# the common case.
if [ -n "${ESP_EXTRA_COMPONENT_DIRS:-}" ]; then
  IDF_ARGS+=("-DEXTRA_COMPONENT_DIRS=${ESP_EXTRA_COMPONENT_DIRS}")
fi
idf.py "${IDF_ARGS[@]}" build

grep -q " app_main" build/pxx_hello_esp32.map && echo "app_main present in image map"
