#!/bin/sh
# onsite.sh WORKDIR [DESTDIR]: build GNU make from the recipe with only pxx,
# a POSIX shell and toybox-level tools (zcat, tar, sha256sum). No gcc, make
# or configure: what configure decided was recorded on the build host
# (record.sh) and comes in gen.tar, `units` and `link`. GNU make is what the
# Rainyday kernel's own build needs, so this comes before the kernel.
#
#   DL=/iso/dl PXX=pxx sh /iso/recipe/make/onsite.sh /tmp/make [/mnt/target]
#
# DL: the directory holding the tarball named in sources.list. PXX: the pxx
# compiler (default `pxx`). JOBS: parallel compiles (default 2). RECIPE: the
# recipe directory (default: this script's). With DESTDIR, installs
# DESTDIR/bin/make. Exit status 0 only if every unit compiled and the new
# make runs a smoke makefile (pattern rules, $(foreach), $(call), $(shell)).
set -eu
R=${RECIPE:-$(cd "$(dirname "$0")" && pwd)}
DL=${DL:?set DL to the directory with the source tarball}
PXX=${PXX:-pxx}
JOBS=${JOBS:-2}
WORK=${1:?usage: onsite.sh WORKDIR [DESTDIR]}
DEST=${2:-}

read -r name sum < "$R/sources.list"
echo "$sum  $DL/$name" | sha256sum -c - > /dev/null || { echo "onsite: $name: checksum mismatch" >&2; exit 1; }
mkdir -p "$WORK/src" "$WORK/obj"
zcat "$DL/$name" | tar -xf - -C "$WORK/src" --strip-components=1
tar -xf "$R/gen.tar" -C "$WORK/src"

# compile the objects make links, JOBS at a time. A failed unit leaves
# OBJ.fail beside its log.
read -r prog objs < "$R/link"
i=0
for obj in $objs; do
  line=$(grep -m1 "^$obj " "$R/units") || { echo "onsite: no unit for $obj" >&2; exit 1; }
  o=$WORK/obj/$(echo "$obj" | tr / _)
  (
    # shellcheck disable=SC2086 -- the flags are words, with configure's quoting
    set -- $line
    dir=$2; src=$3; shift 3
    cd "$WORK/src/$dir"
    ( eval "\"\$PXX\" --emit-obj --function-sections --shared-runtime -ffile-prefix-map=\"\$WORK/src=/usr/src/make\" $* \"\$src\" \"\$o\"" \
      ) > "$o.log" 2>&1 || : > "$o.fail"
  ) &
  i=$((i + 1))
  if [ "$i" -ge "$JOBS" ]; then wait; i=0; fi
done
wait
for f in "$WORK"/obj/*.fail; do
  [ -e "$f" ] || continue
  echo "onsite: FAILED $(basename "$f" .fail): $(grep -m1 error "${f%.fail}.log")" >&2
  exit 1
done
list=
for obj in $objs; do list="$list $WORK/obj/$(echo "$obj" | tr / _)"; done
# shellcheck disable=SC2086
"$PXX" --link -o "$WORK/make" $list > "$WORK/link.log" 2>&1 || { tail -5 "$WORK/link.log" >&2; exit 1; }

# smoke: the GNU-only features the Rainyday kernel's build uses
S=$WORK/smoke
mkdir -p "$S"
printf 'one\n' > "$S/a.in"; printf 'two\n' > "$S/b.in"
cat > "$S/Makefile" <<'EOF'
IN := $(wildcard *.in)
OUT := $(patsubst %.in,%.out,$(IN))
up = $(shell echo $(1) | tr a-z A-Z)
all: $(OUT)
	@echo $(foreach f,$(sort $(OUT)),$(call up,$(f))) $(filter a%,$(OUT))
%.out: %.in
	@cp $< $@
EOF
got=$(cd "$S" && "$WORK/make" -s 2>&1)
[ "$got" = "A.OUT B.OUT a.out" ] || { echo "onsite: smoke makefile printed '$got'" >&2; exit 1; }
cmp -s "$S/a.in" "$S/a.out" || { echo "onsite: the pattern rule did not run" >&2; exit 1; }
echo "onsite: $WORK/make"

if [ -n "$DEST" ]; then
  mkdir -p "$DEST/bin"
  cp "$WORK/make" "$DEST/bin/make"
  chmod 755 "$DEST/bin/make"
  echo "onsite: installed into $DEST"
fi
