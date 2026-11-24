#!/bin/bash
# Path B, host side, after gccbuild.sh: the source edits that are not a gcc
# build. record.py puts their results in the recipe (gen.tar), so on site
# needs neither GNU sed nor this script.
#   st 0.9.2, dwm 6.5: config.h from the default config.def.h
#   LVGL 9.2.2: unpacked, and its lv_conf.h, the template with the edits
#   below (32-bit framebuffer, a heap for the demo, its fonts, the fbdev and
#   evdev drivers, the widgets demo)
set -eu
B=${PATHB_WORK:?set PATHB_WORK}
B=$(cd "$B" && pwd -P)
for d in st-0.9.2 dwm-6.5; do
  [ -f $B/src/$d/config.h ] || cp $B/src/$d/config.def.h $B/src/$d/config.h
done
L=$B/src/lvgl
C=$B/obj/lvgl
mkdir -p $C
[ -f $L/lv_conf_template.h ] || { mkdir -p $L && tar -xzf $B/dl/lvgl-9.2.2.tar.gz -C $L --strip-components=1; }
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
echo "prep done"
