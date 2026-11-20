#!/bin/sh
# Path B end to end: pinned sources -> gcc reference build (its make logs are
# the recipe) -> every compile replayed through pxx -> st, dwm and Xfbdev
# linked by pxx, plus LVGL's framebuffer demo -> pixx's desktop bundle.
#   PATHB_WORK=/some/dir tools/pathb/build.sh
# Env: PXXC (default: this tree's compiler/pascal26), JOBS (default 8).
set -e
T=$(cd "$(dirname "$0")" && pwd)
export PATHB_WORK=${PATHB_WORK:?set PATHB_WORK to an empty or earlier work directory}
mkdir -p "$PATHB_WORK"
# resolved: make logs record real paths, and replay object names derive from them
export PATHB_WORK=$(cd "$PATHB_WORK" && pwd -P)
export PXXC=${PXXC:-$T/../../compiler/pascal26}
export PXX_HOME=${PXX_HOME:-$(cd "$T/../.." && pwd)}
export PXXFLAGS=${PXXFLAGS:---shared-runtime --threadsafe}
sh $T/fetch.sh
bash $T/gccbuild.sh
python3 $T/replay-cc.py xorgproto libXau xtrans libxcb libX11 libXext libXrender expat \
  freetype fontconfig libXft zlib libfontenc libXfont tinyx \
  libICE libSM libXt libXmu libXpm libXaw xclock xcalc xeyes xload xedit jwm
sh $T/link.sh
bash $T/lvgl.sh
sh $T/make_bundle.sh
