#!/usr/bin/env bash
# test-privsep-rainyday.sh: the pxx dhcpcd, with privilege separation and its
# seccomp filter, takes a real lease on Rainyday.
#
# Boots the Rainyday kernel under QEMU (user-mode network: QEMU's DHCP server
# answers) with a busybox root, the on-site rumpnic as the NIC driver and the
# on-site dhcpcd. dhcpcd configures eth0 itself (no udhcpc), then the guest
# pings the gateway, fetches a file from the host, and reports every dhcpcd
# process's uid and seccomp mode from /proc. The _dhcpcd account and its home
# (the chroot) are the ones onsite.sh installed into DHCPCD_DESTDIR's
# etc/passwd and etc/group, not added here: a system installed from the
# recipe must have them, or dhcpcd runs every process as root.
# PASS: the lease is bound, the ping and the fetch succeed, at least one
# dhcpcd process runs as _dhcpcd under a seccomp filter, and every other one
# is the privileged proxy (root, by its process title).
#
#   tools/nodisx/dhcpcd/test-privsep-rainyday.sh DHCPCD_DESTDIR BUSYBOX RUMPNIC [KERNEL]
# DHCPCD_DESTDIR is what onsite.sh installed (sbin/dhcpcd, libexec/, etc/).
# BUSYBOX and RUMPNIC are built by pxx (their recipes). KERNEL defaults to
# ~/rainyday/kernel/build/pxx/rainyday.elf. Rainyday's tools/mkroot-busybox.sh
# builds the root.
set -euo pipefail
dest=${1:?usage: test-privsep-rainyday.sh DHCPCD_DESTDIR BUSYBOX RUMPNIC [KERNEL]}
bb=${2:?busybox} rn=${3:?rumpnic}
RD=${RAINYDAY:-$HOME/rainyday}
kernel=${4:-$RD/kernel/build/pxx/rainyday.elf}
pw=$(grep '^_dhcpcd:' "$dest/etc/passwd" 2>/dev/null) && gr=$(grep '^_dhcpcd:' "$dest/etc/group" 2>/dev/null) \
  || { echo "test-privsep: onsite.sh did not install the _dhcpcd user and group into $dest/etc"; exit 1; }
uid=$(echo "$pw" | cut -d: -f3) home=$(echo "$pw" | cut -d: -f6)
[[ $uid != 0 && -d $dest$home ]] || { echo "test-privsep: _dhcpcd is uid $uid, home $home (not installed)"; exit 1; }
work=$(mktemp -d "${TMPDIR:-/tmp}/nodisx-dhcpcd-ps.XXXXXX")
mkdir -p "$work/www"
head -c 300000 /dev/urandom > "$work/www/blob"
sum=$(md5sum < "$work/www/blob" | cut -d' ' -f1)
port=$((20000 + RANDOM % 20000))
python3 -m http.server "$port" --bind 127.0.0.1 --directory "$work/www" > "$work/http.log" 2>&1 &
http=$!
trap 'kill $http 2>/dev/null' EXIT
cat > "$work/run.sh" <<EOF
#!/bin/sh
exec </dev/console >/dev/console 2>&1
mkdir -p /proc /sys /tmp /var/run/dhcpcd
mount -t proc proc /proc
mount -t sysfs sys /sys
ip link set lo up
echo '$pw' >> /etc/passwd
echo '$gr' >> /etc/group
/bin/rumpnic -v > /tmp/rn.log 2>&1 &
i=0; while ! grep -q 'bridged to' /tmp/rn.log && [ \$i -lt 300 ]; do usleep 100000; i=\$((i+1)); done
ifc=\$(sed -n 's/.* bridged to \([a-z0-9]*\).*/\1/p' /tmp/rn.log)
ip link set \$ifc up
/sbin/dhcpcd -4 -w -t 40 \$ifc > /tmp/dh.log 2>&1; echo "dps: dhcpcd rc=\$?"
sed 's/^/dps: log: /' /tmp/dh.log | tail -n 25
ip -4 -o addr show dev \$ifc | sed -n 's/.* inet \([0-9./]*\).*/dps: got \1/p'
ip route | grep -q '^default via 10.0.2.2' && echo "dps: default route"
for p in /proc/[0-9]*; do
  case "\$(tr '\0' ' ' < \$p/cmdline 2>/dev/null)" in
    *dhcpcd*) echo "dps: proc \$(tr '\0' ' ' < \$p/cmdline | cut -c1-40)| uid \$(sed -n 's/^Uid:[[:space:]]*\([0-9]*\).*/\1/p' \$p/status) seccomp \$(sed -n 's/^Seccomp:[[:space:]]*//p' \$p/status)" ;;
  esac
done
ping -c 3 -W 2 10.0.2.2 | grep -q ' 0% packet loss' && echo "dps: ping ok"
wget -q -O /tmp/b http://10.0.2.2:$port/blob && echo "dps: fetched \$(md5sum < /tmp/b | cut -d' ' -f1)"
grep -q '^nameserver 10.0.2.3' /etc/resolv.conf 2>/dev/null && echo "dps: hooks wrote resolv.conf"
/sbin/dhcpcd -4 -x \$ifc > /tmp/dx.log 2>&1; echo "dps: stopped rc=\$?"
sed 's/^/dps: stop: /' /tmp/dx.log | tail -n 8
echo DPS-DONE
poweroff -f
EOF
chmod 755 "$work/run.sh"
specs=("sbin/dhcpcd=$dest/sbin/dhcpcd" "etc/dhcpcd.conf=$dest/etc/dhcpcd.conf"
       "libexec/dhcpcd-run-hooks=$dest/libexec/dhcpcd-run-hooks" "bin/rumpnic=$rn" "var/db/dhcpcd/" "${home#/}/")
for h in "$dest"/libexec/dhcpcd-hooks/*; do specs+=("libexec/dhcpcd-hooks/$(basename "$h")=$h"); done
"$RD/tools/mkroot-busybox.sh" "$work/root.cpio" "$bb" "$work/run.sh" "${specs[@]}" > /dev/null
timeout 240 qemu-system-x86_64 -enable-kvm -cpu host -machine q35 -m 512M -kernel "$kernel" \
  -initrd "$work/root.cpio" -serial "file:$work/console" -display none -no-reboot \
  -netdev user,id=n0 -device e1000,netdev=n0 -append "vfio-pci.ids=8086:100e" < /dev/null > /dev/null 2>&1 || true
tr -d '\r' < "$work/console" > "$work/out"
c=$work/out
grep -a '^dps:\|unsupported syscall\|seccomp' "$c" || true
ok=1
need() { grep -aq "$1" "$c" || { echo "test-privsep: missing: $1"; ok=0; }; }
need '^dps: dhcpcd rc=0$'
need '^dps: got 10\.0\.2\.'
need '^dps: default route$'
need "^dps: proc .*| uid $uid seccomp 2\$"
# dhcpcd's own errors: a directory the install should have made, a lease
# file it could not write
grep -a '^dps: log: .*\(No such file or directory\|Permission denied\)' "$c" && { echo "test-privsep: dhcpcd could not reach a file"; ok=0; }
# the rest: root is the privileged proxy alone (Rainyday's /proc/N/cmdline
# shows dhcpcd's setproctitle titles)
other=$(grep -a '^dps: proc ' "$c" | grep -v "| uid $uid seccomp 2\$" | grep -v '\[privileged proxy\].*| uid 0 ' || true)
[[ -z $other ]] || { echo "test-privsep: a dhcpcd process neither _dhcpcd under seccomp nor the privileged proxy:"; echo "$other"; ok=0; }
need '^dps: hooks wrote resolv.conf$'
need '^dps: ping ok$'
need '^dps: stopped rc=0$'
need "^dps: fetched $sum\$"
grep -aq '^DPS-DONE' "$c" || { echo "test-privsep: did not finish"; ok=0; }
echo "test-privsep: console in $work/out"
if [[ $ok == 1 ]]; then echo "test-privsep: PASS"; else echo "test-privsep: FAIL"; exit 1; fi
