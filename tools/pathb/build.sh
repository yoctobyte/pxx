#!/bin/sh
# Path B on the HOST: pinned sources -> gcc reference build (its make logs
# are the recipe) -> the on-site recipe -> the very steps the target runs
# (onsite.sh: every compile and link by pxx) -> pixx's desktop bundle and
# bundle.manifest. A target given $PATHB_WORK/recipe and the pinned tarballs
# runs onsite.sh alone and gets the same manifest.
#   PATHB_WORK=/some/dir tools/pathb/build.sh
# Env: PXXC (default: this tree's compiler/pascal26), JOBS (default 8).
# Host tools beyond the target's: gcc, make, autoconf, python3, patch, nm,
# ar, bdftopcf, ucs2any, mkfontdir.
set -e
T=$(cd "$(dirname "$0")" && pwd)
export PATHB_WORK=${PATHB_WORK:?set PATHB_WORK to an empty or earlier work directory}
mkdir -p "$PATHB_WORK"
# resolved: make logs record real paths, and replay object names derive from them
export PATHB_WORK=$(cd "$PATHB_WORK" && pwd -P)
export PXX=${PXXC:-$T/../../compiler/pascal26}
export PXX_HOME=${PXX_HOME:-$(cd "$T/../.." && pwd)}
export JOBS=${JOBS:-8}
sh $T/fetch.sh
bash $T/gccbuild.sh
bash $T/prep.sh
sh $T/fonts.sh
python3 $T/record.py
# unpack keeps the gcc trees and lays gen.tar over them, as the target does
sh $T/onsite.sh $PATHB_WORK unpack compile
sh $T/linkplan.sh
sh $T/onsite.sh $PATHB_WORK link bundle
