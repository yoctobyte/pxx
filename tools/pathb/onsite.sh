#!/bin/sh
# Path B ON SITE: build pixx's desktop bundle from the pinned sources and a
# recorded recipe, with only pxx, a POSIX shell and toybox-level tools (tar,
# xzcat/bzcat/zcat, sed, sort, sha256sum, find, stat, cp, chmod). No gcc,
# make, autoconf, python, ar, nm or objcopy. The host build (build.sh) runs
# these same steps on the recipe it records, so both make the same bundle.
#
#   onsite.sh WORKDIR [STAGE...]     STAGE: unpack compile link bundle (default: all)
# Env:
#   RECIPE   the recipe dir (default WORKDIR/recipe; record.py writes it)
#   DL       the pinned source tarballs (default WORKDIR/dl; tools/pathb/fetch.sh)
#   PXX      the pxx compiler (default: pxx on PATH); PXX_HOME as pxx needs it
#   JOBS     parallel compiles (default 4)
# Out: WORKDIR/bundle/pixx-pathb-desktop-x86_64.tar.gz and bundle.manifest
# (sha256, mode and path of every file: the check that two builds agree).
# Every object depends only on the sources and the recipe, not on WORKDIR:
# each compile maps WORKDIR to /usr/src/pathb (-ffile-prefix-map), and every
# path a program looks up at run time is the target's (/usr, /etc, /var).
set -eu
W=${1:?usage: onsite.sh WORKDIR [unpack|compile|link|bundle]...}
shift
mkdir -p "$W"
W=$(cd "$W" && pwd -P)
case $W in *'|'*|*'	'*|*' '*) echo "onsite.sh: WORKDIR may not contain '|', a tab or a space"; exit 1 ;; esac
RECIPE=${RECIPE:-$W/recipe}
DL=${DL:-$W/dl}
PXX=${PXX:-pxx}
JOBS=${JOBS:-4}
TAB=$(printf '\t')
STAGES=${*:-unpack compile link bundle}
mkdir -p "$W/build"

say() { echo "onsite: $*"; }

# the recipe's lists name the work dir @W@
instantiate() {  # list -> $W/build/list
  sed "s|@W@|$W|g" "$RECIPE/$1" > "$W/build/$1"
}

unpack() {
  while IFS="$TAB" read -r d t; do
    [ -n "$d" ] || continue
    if [ -d "$W/src/$d" ]; then say "keep src/$d"; continue; fi
    # into NAME.part, renamed when complete: an interrupted run leaves no
    # half tree under the real name
    if [ -e "$W/src/$d.part" ]; then mv "$W/src/$d.part" "$W/build/$d.part.old.$$"; fi
    mkdir -p "$W/src/$d.part"
    case $t in
      *.tar.xz)  xzcat "$DL/$t" ;;
      *.tar.bz2) bzcat "$DL/$t" ;;
      *.tar.gz)  zcat "$DL/$t" ;;
      *) echo "onsite.sh: unknown archive $t"; exit 1 ;;
    esac | tar -xf - -C "$W/src/$d.part" --strip-components=1
    mv "$W/src/$d.part" "$W/src/$d"
  done < "$RECIPE/sources.list"
  # what the gcc build generated or changed, the staged headers and data
  zcat "$RECIPE/gen.tar.gz" | tar -xf - -C "$W"
  say "unpacked $(grep -c . "$RECIPE/sources.list") sources and gen.tar"
}

# one line: PKG TAB CWD TAB OUT TAB ARG...  ->  cd CWD; pxx ARG... OUT
compile_one_list() {  # file
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    set -f; oIFS=$IFS; IFS=$TAB
    # shellcheck disable=SC2086
    set -- $line
    IFS=$oIFS; set +f
    pkg=$1 cwd=$2 out=$3; shift 3
    mkdir -p "${out%/*}"
    if ( cd "$cwd" && "$PXX" "$@" "$out" ) > "$out.log" 2>&1; then :; else
      echo "FAIL $pkg ${out#$W/}: $(grep -m1 error "$out.log" || true)"
      echo "$out" >> "$W/build/failed"
    fi
  done < "$1"
}

compile() {
  instantiate compile.list
  : > "$W/build/failed"
  # deal the lines round-robin to JOBS lists, run those side by side
  j=0
  while [ $j -lt "$JOBS" ]; do : > "$W/build/job.$j"; j=$((j + 1)); done
  n=0
  while IFS= read -r line; do
    printf '%s\n' "$line" >> "$W/build/job.$((n % JOBS))"
    n=$((n + 1))
  done < "$W/build/compile.list"
  j=0
  while [ $j -lt "$JOBS" ]; do compile_one_list "$W/build/job.$j" & j=$((j + 1)); done
  wait
  f=$(grep -c . "$W/build/failed" || true)
  say "compiled $((n - f))/$n"
  [ "$f" = 0 ] || exit 1
}

# one line: OUT TAB OBJ...  ->  pxx --link -o OUT OBJ...
link() {
  instantiate link.list
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    set -f; oIFS=$IFS; IFS=$TAB
    # shellcheck disable=SC2086
    set -- $line
    IFS=$oIFS; set +f
    out=$1; shift
    mkdir -p "${out%/*}"
    "$PXX" --link -o "$out" "$@" > "$out.link.log" 2>&1 \
      || { echo "LINK FAIL ${out#$W/}: $(tail -3 "$out.link.log")"; exit 1; }
    say "linked ${out#$W/}"
  done < "$W/build/link.list"
}

bundle() {
  W=$W RECIPE=$RECIPE DL=$DL sh "$RECIPE/tools/make_bundle.sh"
}

for s in $STAGES; do
  case $s in
    unpack|compile|link|bundle) $s ;;
    *) echo "onsite.sh: unknown stage $s"; exit 1 ;;
  esac
done
