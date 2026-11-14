# Shared by the ReactOS harness scripts (sourced): paths and the one qemu
# command line. loadvm needs the same devices savevm had, so every run goes
# through rosqemu.
#   PXX_ROS_DIR  where the live CD ISO and the snapshot live (/data/vm/reactos)
# ide0: data disk (qcow2, holds the snapshot); ide1: the boot CD; ide2: the
# swap CD drive, empty in the snapshot, where a batch's ISO is inserted.
S=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$S/../../.." && pwd)
R=${PXX_ROS_DIR:-/data/vm/reactos}
SN=$R/snap
kvm=""; [ -w /dev/kvm ] && kvm="-enable-kvm -cpu host"
rosqemu() {
  qemu-system-x86_64 $kvm -m 2048 -smp 2 \
    -drive file=$SN/data.qcow2,format=qcow2,if=ide,index=0 \
    -drive file=$SN/ros-snap.iso,format=raw,if=ide,index=1,media=cdrom,readonly=on \
    -drive if=ide,index=2,media=cdrom,id=swapcd \
    -boot d -display none -serial file:$SN/serial.log -monitor unix:$SN/mon.sock,server,nowait -net none "$@"
}
