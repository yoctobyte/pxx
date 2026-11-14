#!/bin/bash
# One-time setup for rosbatch.sh: boot the ReactOS x64 live CD to the desktop
# with a StartUp script that polls every drive for \run.cmd, then save the
# running VM as qemu snapshot "ready" (inside $SN/data.qcow2).
# Needs $PXX_ROS_DIR/reactos-livecd-*.iso (an x64 nightly from
# iso.reactos.org/livecd), qemu, xorriso, sfdisk, mkfs.fat, mtools, python3
# with PIL. About 4 minutes under KVM. Re-run it after replacing the ISO;
# never rebuild ros-snap.iso without re-taking the snapshot.
set -u
. "$(dirname "$0")/roscommon.sh"
mkdir -p $SN
ISO=$(ls $R/reactos-livecd-*.iso | head -1)
[ -f "$ISO" ] || { echo "no live CD ISO in $R"; exit 1; }
# StartUp poller: run.cmd gets its own drive as %1, then the VM powers off
printf '@echo off\r\n:w\r\nset R=\r\nfor %%%%d in (C D E F G H I) do if exist %%%%d:\\run.cmd set R=%%%%d:\r\nif not "%%R%%"=="" goto go\r\ntimeout /t 2 /nobreak > nul\r\ngoto w\r\n:go\r\ncall %%R%%\\run.cmd %%R%%\r\nshutdown -s -t 0\r\n' > $SN/pxxstart.cmd
# The default entry (LiveCD_Debug) waits for a kernel debugger on COM1
rm -f $SN/freeldr.orig
xorriso -osirrox on -indev $ISO -extract /freeldr.ini $SN/freeldr.orig >/dev/null 2>&1 || { echo "cannot read freeldr.ini"; exit 1; }
sed "s/^DefaultOS=.*/DefaultOS=LiveCD/" $SN/freeldr.orig > $SN/freeldr.ini
rm -f $SN/ros-snap.iso
# Plain ISO 9660 names (no ";1", no Rock Ridge/Joliet): freeldr cannot load
# the hives otherwise ("Could not load SYSTEM.ALT hive!")
xorriso -indev $ISO -outdev $SN/ros-snap.iso -rockridge off -joliet off \
  -compliance iso_9660_level=3:omit_version:no_force_dots:lowercase:full_ascii:long_paths:long_names:deep_paths \
  -map $SN/freeldr.ini /freeldr.ini \
  -map $SN/pxxstart.cmd "/Profiles/All Users/Start Menu/Programs/StartUp/pxxstart.cmd" \
  -boot_image any replay >/dev/null 2>&1 || { echo "xorriso failed"; exit 1; }
# data disk: MBR + one FAT32 partition at 1 MiB (ReactOS does not mount a
# bare "superfloppy" volume), with the pxxmark marker run.cmd looks for
rm -f $SN/data.raw $SN/data.qcow2
truncate -s 300M $SN/data.raw
echo 'start=2048, type=c' | sfdisk -q $SN/data.raw
mkfs.fat -F 32 --offset 2048 $SN/data.raw 300000 >/dev/null 2>&1
echo x > $SN/pxxmark
mcopy -i $SN/data.raw@@1M $SN/pxxmark ::/
qemu-img convert -O qcow2 $SN/data.raw $SN/data.qcow2
rm -f $SN/data.raw $SN/mon.sock
rosqemu &
QP=$!
# a disk attached at boot makes the CD ask "press any key"
( sleep 1; python3 $S/mon.py $SN/mon.sock 'sendkey ret' 8 1 ) &
python3 $S/roswait.py $SN wizard 900 || { echo "no wizard"; kill $QP; exit 1; }
python3 $S/mon.py $SN/mon.sock 'sendkey ret'
python3 $S/roswait.py $SN desktop 300 || { echo "no desktop"; kill $QP; exit 1; }
python3 $S/roswait.py $SN settle 45
python3 $S/roswait.py $SN cmd "screendump $SN/ready.ppm" >/dev/null
python3 $S/roswait.py $SN cmd 'savevm ready' >/dev/null
python3 $S/mon.py $SN/mon.sock 'quit'
wait $QP
qemu-img snapshot -l $SN/data.qcow2
