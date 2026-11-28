#!/bin/sh
# onsite-all.sh ISO DESTDIR [WORK]: build every recipe on the ISO, in order,
# on the target, with what is there: pxx, a POSIX shell and toybox-level
# tools. Each tool installs into DESTDIR and DESTDIR/bin comes first on PATH,
# so later recipes use what earlier ones built (GNU make, xz, ...).
#
#   PXX=/iso/pxx/compiler/pascal26 sh /iso/onsite-all.sh /iso /mnt/target
#
# ISO: holds recipe/<tool>/ and dl/ (tools/nodisx/mkiso-tree.sh writes it).
# PXX: the pxx compiler (default `pxx`). JOBS: parallel compiles per recipe
# (default 2). WORK: scratch (default /tmp/nodisx-onsite). ONLY="a b": just
# those tools. Prints one line per tool and a last line
# `onsite-all: N built, M failed`; exit status 0 only if none failed.
set -u
ISO=${1:?usage: onsite-all.sh ISO DESTDIR [WORK]}
DEST=${2:?usage: onsite-all.sh ISO DESTDIR [WORK]}
WORK=${3:-/tmp/nodisx-onsite}
export PXX=${PXX:-pxx} JOBS=${JOBS:-2} DL=$ISO/dl
# the order: the shell and tools first, GNU make before what may want it,
# the compressors before what unpacks with them, the userland, the drivers
ORDER="toybox mksh make xz bzip2 zstd dosfstools e2fsprogs util-linux dhcpcd dropbear curl git sqlite busybox limine rumpnic"
mkdir -p "$DEST/bin" "$WORK"
PATH=$DEST/bin:$PATH
export PATH
ok=0 bad=0
for t in $ORDER; do
  [ -f "$ISO/recipe/$t/onsite.sh" ] || continue
  if [ -n "${ONLY:-}" ]; then
    case " $ONLY " in *" $t "*) ;; *) continue ;; esac
  fi
  s=$(date +%s)
  if RECIPE=$ISO/recipe/$t sh "$ISO/recipe/$t/onsite.sh" "$WORK/$t" "$DEST" > "$WORK/$t.log" 2>&1; then
    echo "onsite-all: $t built ($(( $(date +%s) - s )) s)"
    ok=$((ok + 1))
  else
    echo "onsite-all: $t FAILED ($(( $(date +%s) - s )) s):"
    tail -5 "$WORK/$t.log" | sed 's/^/  /'
    bad=$((bad + 1))
  fi
done
echo "onsite-all: $ok built, $bad failed"
[ "$bad" = 0 ]
