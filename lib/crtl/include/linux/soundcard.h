/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: <linux/soundcard.h> -- the OSS mixer subset (`mix`).
 *
 * Written for pxx from the kernel's documented ABI (the numbers are the ABI,
 * checked against a gcc build over the system header on x86-64 and i386);
 * only what userland tools reach. Without it a native x86-64 build silently
 * took the HOST's copy and every cross target failed to find one.
 * Found building toybox (feature-c-toybox-builds-with-pxx).
 */
#ifndef PXX_CRTL_LINUX_SOUNDCARD_H
#define PXX_CRTL_LINUX_SOUNDCARD_H 1

#include <sys/ioctl.h>

#define SOUND_MIXER_NRDEVICES 25
#define SOUND_DEVICE_NAMES \
  {"vol", "bass", "treble", "synth", "pcm", "speaker", "line", "mic", "cd", \
   "mix", "pcm2", "rec", "igain", "ogain", "line1", "line2", "line3", \
   "dig1", "dig2", "dig3", "phin", "phout", "video", "radio", "monitor"}

#define SOUND_MIXER_RECSRC    0xff
#define SOUND_MIXER_DEVMASK   0xfe
#define SOUND_MIXER_RECMASK   0xfd
#define SOUND_MIXER_CAPS      0xfc
#define SOUND_MIXER_STEREODEVS 0xfb

#define MIXER_READ(dev)  _IOR('M', dev, int)
#define MIXER_WRITE(dev) _IOWR('M', dev, int)
#define SOUND_MIXER_READ_DEVMASK    MIXER_READ(SOUND_MIXER_DEVMASK)
#define SOUND_MIXER_READ_RECMASK    MIXER_READ(SOUND_MIXER_RECMASK)
#define SOUND_MIXER_READ_RECSRC     MIXER_READ(SOUND_MIXER_RECSRC)
#define SOUND_MIXER_READ_STEREODEVS MIXER_READ(SOUND_MIXER_STEREODEVS)
#define SOUND_MIXER_READ_CAPS       MIXER_READ(SOUND_MIXER_CAPS)

#endif
