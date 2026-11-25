/* The kernel's DRM UAPI headers through crtl: <drm/drm.h> needs
   <linux/types.h> to bring the __kernel_* types (__kernel_size_t) and
   <asm/ioctl.h> the _IOC encoding. Struct sizes, member offsets and ioctl
   numbers must match gcc's, or every ioctl a KMS client makes is wrong.
   Found compiling libdrm and Rainyday's kmstest.c (2026-11-25). */
#include <stdio.h>
#include <stddef.h>
#include <drm/drm.h>
#include <drm/drm_mode.h>

#define SZ(t) printf("%-28s %3u\n", #t, (unsigned)sizeof(t))
#define OFF(t, m) printf("%-28s %3u\n", #t "." #m, (unsigned)offsetof(t, m))
#define IOC(n) printf("%-28s %08lx\n", #n, (unsigned long)(n))

int main(void)
{
    SZ(struct drm_version);
    OFF(struct drm_version, name_len);
    OFF(struct drm_version, desc);
    SZ(struct drm_mode_card_res);
    SZ(struct drm_mode_get_connector);
    SZ(struct drm_mode_modeinfo);
    SZ(struct drm_mode_crtc);
    SZ(struct drm_mode_create_dumb);
    OFF(struct drm_mode_create_dumb, size);
    SZ(struct drm_mode_map_dumb);
    SZ(struct drm_mode_fb_cmd);
    SZ(struct drm_mode_fb_cmd2);
    OFF(struct drm_mode_fb_cmd2, modifier);
    SZ(struct drm_event_vblank);
    SZ(__kernel_size_t);
    IOC(DRM_IOCTL_VERSION);
    IOC(DRM_IOCTL_SET_MASTER);
    IOC(DRM_IOCTL_MODE_GETRESOURCES);
    IOC(DRM_IOCTL_MODE_GETCONNECTOR);
    IOC(DRM_IOCTL_MODE_SETCRTC);
    IOC(DRM_IOCTL_MODE_CREATE_DUMB);
    IOC(DRM_IOCTL_MODE_MAP_DUMB);
    IOC(DRM_IOCTL_MODE_ADDFB2);
    IOC(DRM_IOCTL_MODE_PAGE_FLIP);
    return 0;
}
