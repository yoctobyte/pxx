#!/bin/sh
# test.sh: PASS/FAIL for the rumpnic recipe, on the build host.
#
# Replays the recorded recipe with onsite.sh as the target would (pxx only:
# no gcc, ar, nm, objcopy or python), then boots it: Rainyday's own
# tools/rumpnictest.sh runs the on-site rumpnic in a Rainyday guest under
# QEMU, on an e1000 (NetBSD's wm) and on an rtl8139 behind an IOMMU as uid
# 150 under seccomp (NetBSD's re), as Rainyday's regress.sh runs its all-pxx
# rumpnic: DHCP, ping and a fetch through each. PASS is both.
#
#   NODISX_WORK=/data/tmp/nodisx tools/nodisx/rumpnic/test.sh
# Needs record.sh to have run; RAINYDAY (default ~/rainyday) with a built
# kernel (KERNEL, default its kernel/build/pxx/rainyday.elf) and BB, a
# busybox for the guest (default ~/rainyday-payload/busybox-pxx2829), QEMU.
set -eu
T=$(cd "$(dirname "$0")" && pwd)
W=${NODISX_WORK:?set NODISX_WORK to a work directory}
PXX=${PXX:-$(cd "$T/../../.." && pwd)/compiler/pascal26}
RD=$(cd "${RAINYDAY:-$HOME/rainyday}" && pwd)
KERNEL=${KERNEL:-$RD/kernel/build/pxx/rainyday.elf}
BB=${BB:-$HOME/rainyday-payload/busybox-pxx2829}
R=$W/recipe/rumpnic
[ -f "$R/units" ] || { echo "test: no recipe; run record.sh first" >&2; exit 1; }
O=$W/rumpnic-onsite
rm -rf "$O"
# the target has no gcc, python or binutils: hide them from the replay
mkdir -p "$O/bin"
for t in sh sed tar xzcat sha256sum cat cp mkdir chmod wc grep basename tail rm; do
  ln -s "$(command -v $t)" "$O/bin/$t"
done
env -i PATH="$O/bin" HOME="$O" DL=$W/dl PXX=$PXX JOBS=${JOBS:-3} RECIPE=$R \
  sh "$R/onsite.sh" "$O/work" "$O/root"
fail=0
for v in e1000:-:- rtl8139:1:150; do
  nic=${v%%:*}; rest=${v#*:}; io=${rest%%:*}; u=${rest#*:}
  [ "$io" = - ] && io=
  [ "$u" = - ] && u=
  NIC=$nic IOMMU=$io DRIVER_ARGS=${u:+"-u $u"} timeout 300 "$RD/tools/rumpnictest.sh" \
    "$KERNEL" "$BB" "$O/work/rumpnic" > "$O/$nic.log" 2>&1 || true
  if grep -q 'rumpnictest: PASS' "$O/$nic.log"; then
    echo "rumpnic on $nic${io:+ (IOMMU)}${u:+ as uid $u}: PASS"
  else
    echo "rumpnic on $nic: FAIL"; tail -15 "$O/$nic.log"; fail=1
  fi
done
size "$O/work/rumpnic" | sed "s|$O/work/||"
if [ "$fail" = 0 ]; then echo "rumpnic recipe: PASS"; else echo "rumpnic recipe: FAIL"; exit 1; fi
