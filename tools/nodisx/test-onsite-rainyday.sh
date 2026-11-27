#!/bin/sh
# test-onsite-rainyday.sh: the whole on-site build, ON Rainyday.
#
# Boots the Rainyday kernel under QEMU with an initramfs holding the ISO tree
# (mkiso-tree.sh: pxx, every recipe, its tarballs) and the bootstrap userland
# the ISO ships as binaries: toybox and mksh, themselves built by pxx (their
# own recipes, run on the host first). Nothing else: no gcc, binutils, make,
# python or busybox. The guest runs onsite-all.sh and exports the installed
# tree. The same onsite-all.sh then runs on the host with the same pxx, and
# PASS is: every recipe built in the guest, and every installed file is
# byte-identical to the host's.
#
#   NODISX_WORK=/data/tmp/nodisx tools/nodisx/test-onsite-rainyday.sh
# KERNEL (default ~/rainyday/kernel/build/pxx/rainyday.elf), RAINYDAY
# (default ~/rainyday, for tools/mkcpio.py), MEM (default 8G), SMP (4),
# JOBS (4), ONLY (a subset of tools, as onsite-all.sh takes it).
set -eu
T=$(cd "$(dirname "$0")" && pwd)
W=${NODISX_WORK:?set NODISX_WORK to a work directory}
RD=$(cd "${RAINYDAY:-$HOME/rainyday}" && pwd)
KERNEL=${KERNEL:-$RD/kernel/build/pxx/rainyday.elf}
PXX=${PXX:-$(cd "$T/../.." && pwd)/compiler/pascal26}
MEM=${MEM:-8G} SMP=${SMP:-4} JOBS=${JOBS:-4}
E=$W/e2e
rm -rf "$E"
mkdir -p "$E"

# the ISO tree
PXX=$PXX sh "$T/mkiso-tree.sh" "$E/iso"
# the bootstrap binaries: toybox and mksh by pxx, from their recipes
for t in toybox mksh; do
  [ -f "$E/iso/recipe/$t/onsite.sh" ] || { echo "test: no $t recipe; record it first" >&2; exit 1; }
  DL=$E/iso/dl PXX=$PXX JOBS=$JOBS RECIPE=$E/iso/recipe/$t sh "$E/iso/recipe/$t/onsite.sh" "$E/boot-$t" "$E/boot" > "$E/boot-$t.log" 2>&1 \
    || { echo "test: bootstrap $t failed" >&2; tail -5 "$E/boot-$t.log" >&2; exit 1; }
done
TB=$E/boot/bin/toybox
[ -x "$TB" ] && [ -x "$E/boot/bin/mksh" ] || { echo "test: bootstrap: no toybox or mksh in $E/boot/bin" >&2; ls -R "$E/boot" >&2; exit 1; }

# the guest's script: build everything, then pack what was installed
cat > "$E/run.sh" <<EOF
#!/bin/sh
export PATH=/bin HOME=/tmp TMPDIR=/tmp
mkdir -p /tmp/dest
echo "e2e: start \$(date +%s)"
PXX=/iso/pxx/compiler/pascal26 JOBS=$JOBS ONLY="\${ONLY:-${ONLY:-}}" sh /iso/onsite-all.sh /iso /tmp/dest /tmp/w
echo "e2e: rc=\$? end \$(date +%s)"
cd /tmp/dest && tar -czf /tmp/out.tar .   # gzip: the export line runs ~20 KB/s
EOF
specs="tmp/ bin/sh=$E/boot/bin/mksh bin/toybox=$TB init.sh=$E/run.sh iso=$E/iso/"
for a in $("$TB" --long | tr ' ' '\n' | sed 's|.*/||' | grep -v '^toybox$' | grep -v '^sh$'); do
  specs="$specs bin/$a=$TB"
done
# shellcheck disable=SC2086
python3 -I "$RD/tools/mkcpio.py" "$E/root.cpio" $specs
echo "test: root $(du -h "$E/root.cpio" | cut -f1)"
accel=
[ -r /dev/kvm ] && [ -w /dev/kvm ] && accel="-enable-kvm -cpu host"
# shellcheck disable=SC2086
timeout "${TIMEOUT:-14400}" qemu-system-x86_64 $accel -smp "$SMP" -m "$MEM" -kernel "$KERNEL" \
  -display none -no-reboot -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
  -serial "file:$E/console.log" -serial "file:$E/out.tar" -initrd "$E/root.cpio" \
  -append "cwd=/ export=/tmp/out.tar -- /bin/sh /init.sh" || true
grep 'onsite-all:\|e2e:' "$E/console.log" | tr -d '\r'
mkdir -p "$E/guest"
tar -xzf "$E/out.tar" -C "$E/guest" 2>/dev/null || { echo "test: no tree came back"; tail -20 "$E/console.log"; exit 1; }

# the host, same driver, same pxx, and like the guest no host headers
PATH=$E/boot/bin:/usr/bin:/bin PXX_NO_HOST_INCLUDE=1 PXX=$PXX JOBS=$JOBS sh "$E/iso/onsite-all.sh" "$E/iso" "$E/host" "$E/hw" > "$E/host.log" 2>&1 || true
fail=0
grep -q 'onsite-all: [0-9]* built, 0 failed' "$E/console.log" || { echo "e2e: a recipe FAILED in the guest"; fail=1; }
( cd "$E/host" && find . -type f | sort ) > "$E/host.files"
( cd "$E/guest" && find . -type f | sort ) > "$E/guest.files"
if ! cmp -s "$E/host.files" "$E/guest.files"; then
  echo "e2e: the installed file lists differ:"; diff "$E/host.files" "$E/guest.files" | head -20; fail=1
fi
nd=0
while read -r f; do
  [ -f "$E/guest/$f" ] || continue
  cmp -s "$E/host/$f" "$E/guest/$f" || { echo "e2e: differs: $f"; nd=$((nd + 1)); }
done < "$E/host.files"
[ "$nd" = 0 ] || fail=1
echo "e2e: $(wc -l < "$E/host.files") files installed, $nd differ between guest and host"
if [ "$fail" = 0 ]; then echo "onsite on Rainyday: PASS"; else echo "onsite on Rainyday: FAIL"; exit 1; fi
