#!/bin/sh
# tools/vm/objlink.sh OS COMPILER OUTDIR LIB.pas MAIN.c [pxx flags...]
#
# Builds LIB.pas (test/test_os_objlink.pas) for --os=OS twice, as an --emit-obj object
# and as a --shared library, links each into MAIN.c
# with the VM's own cc, runs both there and prints their output. The test-<OS>
# targets compare that with the same pair linked by gcc on Linux. OS is
# freebsd, netbsd, openbsd or dragonfly; the VM must be up
# (tools/vm/<OS>.sh start). OS=linux builds the reference pair here, with gcc.
set -e
os=$1; pxx=$2; d=$3; src=$4; main=$5; shift 5
if [ "$os" = linux ]; then
  "$pxx" "$@" --emit-obj $src $d/objlink_lx.o >/dev/null
  "$pxx" "$@" --shared $src $d/libpxxobjlinklx.so >/dev/null
  gcc $main $d/objlink_lx.o -o $d/objlink_o
  gcc $main -L$d -lpxxobjlinklx -o $d/objlink_s
  echo "-- object"; $d/objlink_o; echo exit=$?
  echo "-- library"; LD_LIBRARY_PATH=$d $d/objlink_s; echo exit=$?
  exit 0
fi
vm=tools/vm/$os.sh
"$pxx" --os=$os "$@" --emit-obj $src $d/objlink.o >/dev/null
"$pxx" --os=$os "$@" --shared $src $d/libpxxobjlink.so >/dev/null
$vm ssh 'rm -rf /tmp/pxxobjlink && mkdir /tmp/pxxobjlink'
$vm ssh 'cat > /tmp/pxxobjlink/objlink.o' < $d/objlink.o
$vm ssh 'cat > /tmp/pxxobjlink/libpxxobjlink.so' < $d/libpxxobjlink.so
$vm ssh 'cat > /tmp/pxxobjlink/main.c' < $main
$vm ssh 'cd /tmp/pxxobjlink && cc main.c objlink.o -o o && cc main.c -L. -lpxxobjlink -o s &&
  echo "-- object" && ./o; echo exit=$? && echo "-- library" && LD_LIBRARY_PATH=/tmp/pxxobjlink ./s; echo exit=$?'
