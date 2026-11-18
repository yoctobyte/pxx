#!/bin/sh
# Path B end to end: pinned sources -> gcc reference build (its make logs are
# the recipe) -> every compile replayed through pxx -> st, dwm and Xfbdev
# linked by pxx -> pixx's desktop bundle.
#   PATHB_WORK=/some/dir tools/pathb/build.sh
# Env: PXXC (default: this tree's compiler/pascal26), JOBS (default 8).
set -e
T=$(cd "$(dirname "$0")" && pwd)
export PATHB_WORK=${PATHB_WORK:?set PATHB_WORK to an empty or earlier work directory}
export PXXC=${PXXC:-$T/../../compiler/pascal26}
export PXX_HOME=${PXX_HOME:-$(cd "$T/../.." && pwd)}
export PXXFLAGS=${PXXFLAGS:---shared-runtime --threadsafe}
sh $T/fetch.sh
bash $T/gccbuild.sh
python3 $T/replay-cc.py xorgproto libXau xtrans libxcb libX11 libXext libXrender expat \
  freetype fontconfig libXft zlib libfontenc libXfont tinyx
sh $T/link.sh
sh $T/make_bundle.sh
