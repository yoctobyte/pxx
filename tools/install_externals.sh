#!/usr/bin/env sh
# SPDX-License-Identifier: MPL-2.0
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
EXTERNAL_DIR="$ROOT/external"
SYNAPSE_DIR="$EXTERNAL_DIR/synapse"
SYNAPSE_REPO="${SYNAPSE_REPO:-https://github.com/geby/synapse.git}"

mkdir -p "$EXTERNAL_DIR"

if [ -d "$SYNAPSE_DIR/.git" ]; then
  git -C "$SYNAPSE_DIR" fetch --depth 1 origin
  git -C "$SYNAPSE_DIR" checkout origin/master
else
  git clone --depth 1 "$SYNAPSE_REPO" "$SYNAPSE_DIR"
fi

git -C "$SYNAPSE_DIR" rev-parse --short HEAD
