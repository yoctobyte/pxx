#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Run an ESP-IDF project's own build.sh OUT OF TREE:
#
#   tools/esp_project_build.sh examples/esp32/nilpy-c3 [build.sh args...]
#
# Stages the project under $TMPDIR (tools/esp_stage.sh says why and how),
# holds the same per-checkout, per-project lock tools/esp_run.sh and
# tools/esp_flash.sh take, and execs the STAGED build.sh with the given
# arguments, so its exit status is build.sh's own. The caller must already
# have sourced ESP-IDF's export.sh, as it had to for build.sh before.
set -u
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
PROJ="$(cd "${1:?usage: tools/esp_project_build.sh <idf-project-dir> [build.sh args]}" && pwd)" || exit 2
shift
[ -x "$PROJ/build.sh" ] || { echo "esp_project_build: $PROJ has no executable build.sh" >&2; exit 2; }
# shellcheck disable=SC1091
. "$ROOT/tools/esp_stage.sh"
STAGED="$(esp_stage_path "$PROJ")"
mkdir -p "$STAGED"
exec 9<"$STAGED"
flock 9
esp_stage_sync "$PROJ" "$STAGED" || { echo "esp_project_build: staging $PROJ failed" >&2; exit 1; }
cd "$STAGED" || exit 1
exec ./build.sh "$@"
