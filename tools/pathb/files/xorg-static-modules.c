/*
 * Path B: the modules linked into the static Xorg (pxx has no dlopen).
 * patches/xorg-server-static-modules.patch gives the server an empty weak
 * LoaderStaticModules; this strong one replaces it in the pxx link, and
 * LoadModule("modesetting") etc. then finds the module here instead of a
 * .so under ModulePath. fb, ddc, i2c, ramdac, dbe, record, extmod are
 * built into the server already.
 * Compiled with the flags of the server's hw/xfree86/loader/loader.c.
 */
#ifdef HAVE_XORG_CONFIG_H
#include <xorg-config.h>
#endif
#include <stddef.h>
#include "xf86Module.h"

extern XF86ModuleData shadowModuleData;       /* hw/xfree86/dixmods/shmodule.c */
extern XF86ModuleData modesettingModuleData;  /* hw/xfree86/drivers/modesetting */
extern XF86ModuleData evdevModuleData;        /* xf86-input-evdev */

LoaderStaticModule LoaderStaticModules[] = {
    { "shadow", &shadowModuleData },
    { "modesetting", &modesettingModuleData },
    { "evdev", &evdevModuleData },
    { NULL, NULL }
};
