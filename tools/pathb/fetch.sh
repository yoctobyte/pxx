#!/bin/sh
# Download every Path B source listed in sources.lock into $PATHB_WORK/dl and
# check its sha256. A file already present is only re-checked.
set -eu
T=$(cd "$(dirname "$0")" && pwd)
W=${PATHB_WORK:?set PATHB_WORK to a work directory}
mkdir -p "$W/dl"
bad=0
grep -v '^#' "$T/sources.lock" | while read -r f sum url; do
  [ -n "$f" ] || continue
  if [ ! -f "$W/dl/$f" ]; then
    echo "fetch $f"
    curl -sSfL -o "$W/dl/$f.part" "$url"
    mv "$W/dl/$f.part" "$W/dl/$f"
  fi
  echo "$sum  $W/dl/$f" | sha256sum -c --quiet - || { echo "CHECKSUM MISMATCH: $f"; exit 1; }
done
echo "sources ok"
