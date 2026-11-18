#!/bin/bash
# LVGL 9.2.2's widgets demo on /dev/fb0, every file compiled and linked by
# pxx: $PATHB_WORK/bin/lvgl-demo. No X server: LVGL draws straight into
# the framebuffer, pointer from an evdev node (LV_EVDEV=/dev/input/eventN).
# lv_conf.h is LVGL's own template with the edits below.
# JOBS (default 8) parallel compiles. GCC=1 also builds bin/lvgl-demo_gcc.
set -eu
T=$(cd "$(dirname "$0")" && pwd)
B=${PATHB_WORK:?set PATHB_WORK}
B=$(cd "$B" && pwd -P)
PXX=${PXXC:-$T/../../compiler/pascal26}
export PXX_HOME=${PXX_HOME:-$(cd "$T/../.." && pwd)}
L=$B/src/lvgl
C=$B/obj/lvgl
mkdir -p $C/o $C/log $B/bin
[ -f $L/lv_conf_template.h ] || { mkdir -p $L && tar -xzf $B/dl/lvgl-9.2.2.tar.gz -C $L --strip-components=1; }
# the template's BOM is dropped; a 32-bit framebuffer, a heap for the
# demo, its fonts, the fbdev and evdev drivers, the demo itself
sed -e '1s/^\xEF\xBB\xBF//' \
    -e 's|^#if 0 /\*Set it to "1" to enable content\*/|#if 1|' \
    -e 's/^#define LV_COLOR_DEPTH 16/#define LV_COLOR_DEPTH 32/' \
    -e 's|^\( *\)#define LV_MEM_SIZE (64 \* 1024U)|\1#define LV_MEM_SIZE (512 * 1024U)|' \
    -e 's/^#define LV_FONT_MONTSERRAT_\(12\|16\|20\|24\) 0/#define LV_FONT_MONTSERRAT_\1 1/' \
    -e 's/^#define LV_USE_LINUX_FBDEV  *0/#define LV_USE_LINUX_FBDEV 1/' \
    -e 's/^#define LV_USE_EVDEV  *0/#define LV_USE_EVDEV 1/' \
    -e 's/^#define LV_USE_DEMO_WIDGETS 0/#define LV_USE_DEMO_WIDGETS 1/' \
    $L/lv_conf_template.h > $C/lv_conf.h
n=$(grep -c '^#if 1$\|LV_COLOR_DEPTH 32\|(512 \* 1024U)\|MONTSERRAT_\(12\|16\|20\|24\) 1\|LINUX_FBDEV 1\|USE_EVDEV 1\|DEMO_WIDGETS 1' $C/lv_conf.h)
[ "$n" = 10 ] || { echo "lv_conf.h: expected 10 edited lines, got $n (template changed?)"; exit 1; }
INC="-I$C -I$L -DLV_CONF_INCLUDE_SIMPLE"
cd $L
{ find src demos/widgets -name '*.c' | sort; echo demos/lv_demos.c; } > $C/files
one() {
  t=$(echo $1 | tr / _ | sed 's/\.c$//')
  $PXX --emit-obj --shared-runtime $INC $1 $C/o/$t.o > $C/log/$t.log 2>&1 \
    || { echo "PXX FAIL $1: $(grep -a -m1 error $C/log/$t.log)"; return 1; }
  if [ "${GCC:-0}" = 1 ]; then gcc -c -w -O2 $INC $1 -o $C/o/$t.gcc.o; fi
}
export C INC PXX; export -f one
xargs -P ${JOBS:-8} -I{} bash -c 'one {}' < $C/files
$PXX --emit-obj --shared-runtime $INC $T/lvgl/main.c $C/o/main.o > $C/log/main.log 2>&1
$PXX --link -o $B/bin/lvgl-demo $(ls $C/o/*.o | grep -v '\.gcc\.o$') > $C/log/link.log 2>&1 \
  || { tail -3 $C/log/link.log; exit 1; }
if [ "${GCC:-0}" = 1 ]; then
  gcc -c -w -O2 $INC $T/lvgl/main.c -o $C/o/main.gcc.o
  gcc -static -o $B/bin/lvgl-demo_gcc $C/o/*.gcc.o -lm
fi
ls -la $B/bin/lvgl-demo
