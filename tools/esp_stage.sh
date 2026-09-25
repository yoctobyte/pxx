# SPDX-License-Identifier: MPL-2.0
# SOURCED, not run: ESP-IDF builds OUT OF TREE.
#
#   . tools/esp_stage.sh
#   STAGED="$(esp_stage_path "$PROJ")"     # where the project will build
#   esp_stage_sync "$PROJ" "$STAGED"        # copy its sources there
#   cd "$STAGED" && ...                     # build as before
#
# WHY. An IDF build writes build/ (~140-190 MB), sdkconfig, dependencies.lock,
# and our main/main.o + main/libpxx_app.a INTO the project directory. With the
# harnesses building in the checkout, every examples/esp32 project in every
# checkout on the box grew its own build tree. On 2026-09-25 that filled
# plexus's / (140 MB free; one checkout's examples/esp32 alone was 4.0 GB) and
# broke builds for every seat. Now the checkout stays byte-clean and the build
# lives under $TMPDIR, which on plexus is a separate 94 GB volume that the
# tmpfiles reaper clears.
#
# LAYOUT, and why it is not a plain copy. A project's build.sh finds the repo as
# `cd ../../..` (all 25 of them), and the harnesses compile with absolute paths
# into lib/. So the stage mirrors the checkout's shape:
#
#   <stage>/                   one per CHECKOUT (keyed by its path), so two
#                              checkouts never share a build, as before
#     lib, compiler, ...       symlinks to the checkout's entries
#     examples/                real dir; its other entries are symlinks
#       esp32/                 real dir; sibling projects are symlinks
#         <project>/           a REAL copy: sources rsync'd, outputs kept
#
# Build outputs are excluded from the rsync (and so are never deleted by it),
# which keeps a re-run incremental: only a first build after the reaper pays
# the full IDF configure+compile.
#
# Only directories are ever created or updated under the stage. The one
# destructive step, turning a symlink into a real copy, removes the LINK and
# never follows it. That matters, because following it would rsync --delete
# INTO the checkout.

esp_stage_path() {
  # $1 = absolute project dir inside a checkout (…/examples/esp32/<name>)
  local proj="$1" root base key
  root="$(cd "$proj/../../.." && pwd)" || return 1
  key="$(printf '%s' "$root" | sha1sum | cut -c1-12)"
  base="${PXX_ESP_STAGE:-${TMPDIR:-/tmp}/pxx-esp-stage-$(id -u)}/$key"
  printf '%s/examples/esp32/%s\n' "$base" "$(basename "$proj")"
}

# Mirror dir $1 into real dir $2 as symlinks, skipping entry name $3.
_esp_stage_links() {
  local src="$1" dst="$2" skip="$3" e n
  mkdir -p "$dst" || return 1
  for e in "$src"/* "$src"/.[!.]*; do
    [ -e "$e" ] || [ -L "$e" ] || continue
    n="$(basename "$e")"
    [ "$n" = "$skip" ] && continue
    # an entry that is already a real directory here is somebody's staged copy
    [ -d "$dst/$n" ] && [ ! -L "$dst/$n" ] && continue
    ln -sfn "$e" "$dst/$n"
  done
}

esp_stage_sync() {
  # $1 = the checkout's project dir, $2 = esp_stage_path of it
  local proj="$1" staged="$2" root base
  root="$(cd "$proj/../../.." && pwd)" || return 1
  base="${staged%/examples/esp32/*}"
  _esp_stage_links "$root" "$base" examples || return 1
  _esp_stage_links "$root/examples" "$base/examples" esp32 || return 1
  _esp_stage_links "$root/examples/esp32" "$base/examples/esp32" "$(basename "$proj")" || return 1
  # a project staged earlier as a SIBLING is a symlink into the checkout: drop
  # the link itself (rm on a symlink never touches its target) before copying
  if [ -L "$staged" ]; then rm -f "$staged" || return 1; fi
  mkdir -p "$staged" || return 1
  rsync -a --delete \
    --exclude=/build/ --exclude=/sdkconfig --exclude=/sdkconfig.old \
    --exclude=/dependencies.lock --exclude=/managed_components/ \
    --exclude=/main/main.o --exclude=/main/libpxx_app.a \
    "$proj/" "$staged/"
}
