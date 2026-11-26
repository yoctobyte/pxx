#!/bin/sh
# record.sh: write the rumpnic recipe that onsite.sh replays on the target.
#
# HOST SIDE. Needs a gcc rump build (RUMP_TREE, Rainyday's
# tools/rump-build.sh; default ~/rainyday-payload/rump-gcc), a Rainyday
# checkout (RAINYDAY, default ~/rainyday), python3, ar, nm, strace and pxx.
# Writes $NODISX_WORK/recipe/rumpnic/:
#   units        the compile list in link order (mkunits.py: Rainyday's
#                all-pxx method, tools/rump-pxx-build.sh ALLPXX=1, as data)
#   sources.list src.tar.xz and its sha256
# and $NODISX_WORK/dl/src.tar.xz-named rumpnic-src.tar.xz: EXACTLY the files
# the compiles open (every unit compiled once here under strace), under t/
# (the rump tree: NetBSD's sources, buildrump's tools/, the generated headers
# in obj/) and r/ (Rainyday's drivers, uapi headers and the harness's two
# headers). NetBSD's sources are BSD-licensed and Rainyday's MIT;
# NOTICE.netbsd travels with them.
#
#   NODISX_WORK=/data/tmp/nodisx tools/nodisx/rumpnic/record.sh
set -eu
T=$(cd "$(dirname "$0")" && pwd)
W=${NODISX_WORK:?set NODISX_WORK to a work directory}
TREE=$(cd "${RUMP_TREE:-$HOME/rainyday-payload/rump-gcc}" && pwd)
RD=$(cd "${RAINYDAY:-$HOME/rainyday}" && pwd)
PXX=${PXX:-$(cd "$T/../../.." && pwd)/compiler/pascal26}
JOBS=${JOBS:-3}
R=$W/recipe/rumpnic
H=$W/rumpnic-record
rm -rf "$R" "$H"
mkdir -p "$R" "$H/obj" "$W/dl"

libs=$(make -s -C "$RD/drivers" rump-libs)
# shellcheck disable=SC2086
python3 -I "$T/mkunits.py" "$TREE" "$RD" $libs > "$R/units"
echo "record: $(wc -l < "$R/units") units"

# compile each once, here, under strace: what it opens is the source set.
# (No --rename-globals: the rename does not open files.)
one() {
  obj=$1; kind=$2; ren=$3; dir=$4; src=$5; shift 5
  set -- $(echo "$*" | sed "s|@T@|$TREE|g; s|@R@|$RD|g")
  dir=$(echo "$dir" | sed "s|@T@|$TREE|; s|@R@|$RD|")
  src=$(echo "$src" | sed "s|@T@|$TREE|; s|@R@|$RD|")
  case $kind in h) set -- --threadsafe "$@" ;; esac
  ( cd "$dir" && strace -f -qq -e trace=open,openat -e status=successful -o "$H/obj/$obj.trace" \
      "$PXX" --emit-obj "$@" "$src" "$H/obj/$obj" ) > "$H/obj/$obj.log" 2>&1 \
    || echo "record: FAILED $obj: $(grep -m1 error "$H/obj/$obj.log")"
}
i=0
while read -r line; do
  # shellcheck disable=SC2086
  one $line &
  i=$((i + 1))
  if [ "$i" -ge "$JOBS" ]; then wait; i=0; fi
done < "$R/units"
wait
# the files under TREE and RAINYDAY that were opened, relative, t/ and r/
cat "$H"/obj/*.trace | sed -n 's/^[0-9]* *open[at]*([^"]*"\([^"]*\)".*/\1/p' | sort -u > "$H/opened"
: > "$H/files"
while read -r p; do
  case $p in /*) ;; *) continue ;; esac
  [ -f "$p" ] || continue
  q=$(realpath -s "$p")
  case $q in
    "$TREE"/*) echo "t/${q#"$TREE"/}" ;;
    "$RD"/*) echo "r/${q#"$RD"/}" ;;
  esac
done < "$H/opened" | sort -u > "$H/files"
# (a relative path in a trace is relative to its compile's directory; pxx
# opens sources and -I headers by the absolute paths it was given, so the
# check below that the recipe replays from the tarball alone is what proves
# nothing was missed)
echo "r/drivers/rumpnic/NOTICE.netbsd" >> "$H/files"
sort -u -o "$H/files" "$H/files"
mkdir -p "$H/stage"
ln -s "$TREE" "$H/stage/t"
ln -s "$RD" "$H/stage/r"
tar -C "$H/stage" -h --sort=name --owner=0 --group=0 --numeric-owner --mtime=@0 -cf "$H/src.tar" -T "$H/files"
# A shipped file that #includes an ABSOLUTE path under TREE or RAINYDAY
# (buildrump's tools/compat/include/sys/stdint.h does) would only build where
# the host tree sits: on the target that path does not exist. Each gets a
# copy with the path made relative, appended to the tar, so it replaces the
# original on extract. Found by the first on-site build inside Rainyday.
mkdir -p "$H/over"
: > "$H/over.list"
while read -r f; do
  case $f in t/*) abs=$TREE/${f#t/} ;; r/*) abs=$RD/${f#r/} ;; *) continue ;; esac
  grep -qE "^[[:space:]]*#[[:space:]]*include[[:space:]]+\"($TREE|$RD)/" "$abs" || continue
  mkdir -p "$H/over/$(dirname "$f")"
  python3 -I - "$abs" "$f" "$TREE" "$RD" > "$H/over/$f" <<'PY'
import os, re, sys
abs_, rel, tree, rd = sys.argv[1:]
here = os.path.dirname(rel)
def fix(m):
    p = m.group(2)
    for root, pre in ((tree, 't'), (rd, 'r')):
        if p.startswith(root + '/'):
            return m.group(1) + '"' + os.path.relpath(pre + p[len(root):], here) + '"'
    return m.group(0)
sys.stdout.write(re.sub(r'^(\s*#\s*include\s+)"([^"]+)"', fix, open(abs_).read(), flags=re.M))
PY
  echo "$f" >> "$H/over.list"
done < "$H/files"
if [ -s "$H/over.list" ]; then
  tar -C "$H/over" --owner=0 --group=0 --numeric-owner --mtime=@0 -rf "$H/src.tar" -T "$H/over.list"
  echo "record: $(wc -l < "$H/over.list") file(s) had an absolute #include, made relative: $(tr '\n' ' ' < "$H/over.list")"
fi
if grep -rqE "^[[:space:]]*#[[:space:]]*include[[:space:]]+\"($TREE|$RD)/" "$H/over" 2>/dev/null; then
  echo "record: an absolute #include survived" >&2; exit 1
fi
xz -9 -T1 < "$H/src.tar" > "$W/dl/rumpnic-src.tar.xz"
sum=$(sha256sum "$W/dl/rumpnic-src.tar.xz" | cut -d' ' -f1)
echo "rumpnic-src.tar.xz $sum" > "$R/sources.list"
cp "$T/onsite.sh" "$R/onsite.sh"
{ git -C "$T" rev-parse HEAD 2>/dev/null || echo unknown
  echo "rump tree: $TREE (NetBSD $(git -C "$TREE/netbsd" rev-parse --short HEAD 2>/dev/null || echo '?'))"
  echo "rainyday: $(git -C "$RD" rev-parse --short HEAD 2>/dev/null || echo '?')"; } > "$R/RECIPE"
echo "record: $(wc -l < "$H/files") source files, $(wc -c < "$W/dl/rumpnic-src.tar.xz") bytes xz"
