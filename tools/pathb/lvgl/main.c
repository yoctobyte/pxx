/* LVGL 9.2 widgets demo on /dev/fb0, pointer from an evdev device.
   LV_FBDEV (default /dev/fb0), LV_EVDEV (default: none, e.g. /dev/input/event2). */
#include "lvgl.h"
#include "demos/lv_demos.h"
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <unistd.h>

static uint32_t ms(void) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (uint32_t)(t.tv_sec * 1000 + t.tv_nsec / 1000000);
}

int main(void) {
    const char *fb = getenv("LV_FBDEV"), *ev = getenv("LV_EVDEV");
    lv_init();
    lv_tick_set_cb(ms);
    lv_display_t *d = lv_linux_fbdev_create();
    lv_linux_fbdev_set_file(d, fb ? fb : "/dev/fb0");
    printf("lvdemo: %dx%d\n", (int)lv_display_get_horizontal_resolution(d),
           (int)lv_display_get_vertical_resolution(d));
    if (ev) {
        lv_indev_t *p = lv_evdev_create(LV_INDEV_TYPE_POINTER, ev);
        if (p) {
            lv_obj_t *cur = lv_image_create(lv_screen_active());
            lv_image_set_src(cur, LV_SYMBOL_GPS);
            lv_indev_set_cursor(p, cur);
        } else printf("lvdemo: cannot open %s\n", ev);
    }
    lv_demo_widgets();
    fflush(stdout);
    for (;;) {
        uint32_t w = lv_timer_handler();
        usleep((w > 50 ? 50 : w) * 1000);
    }
}
