#!/bin/sh
# fetch.sh [NAME-PREFIX...]: download the Nodisx sources in sources.lock into
# $NODISX_WORK/dl and check each sha256. A file already there is only
# re-checked. With arguments, only the files whose names start with one of them.
# Host side (curl); on site the tarballs come from the ISO.
set -eu
T=$(cd "$(dirname "$0")" && pwd)
W=${NODISX_WORK:?set NODISX_WORK to a work directory}
mkdir -p "$W/dl"
grep -v '^#' "$T/sources.lock" | while read -r f sum url; do
  [ -n "$f" ] || continue
  if [ $# -gt 0 ]; then
    want=0
    for p in "$@"; do case $f in "$p"*) want=1 ;; esac; done
    [ $want = 1 ] || continue
  fi
  if [ ! -f "$W/dl/$f" ]; then
    echo "fetch $f"
    curl -sSfL -o "$W/dl/$f.part" "$url"
    mv "$W/dl/$f.part" "$W/dl/$f"
  fi
  echo "$sum  $W/dl/$f" | sha256sum -c --quiet - || { echo "CHECKSUM MISMATCH: $f"; exit 1; }
done
echo "sources ok"
