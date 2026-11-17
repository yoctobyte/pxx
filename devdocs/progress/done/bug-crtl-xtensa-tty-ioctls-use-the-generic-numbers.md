---
track: ESP
tags: [xtensa, crtl, ioctl, termios, busybox, gibux]
prio: 20
type: bug
blocked-by: []
summary: "crtl's <sys/ioctl.h> and <termios.h> gave xtensa the asm-generic tty and file ioctl numbers, and its header comment claimed xtensa uses them unchanged. Xtensa's asm/ioctls.h keeps TCGETS..TCSETSF and the plain 'T' _IO numbers, but the 't' and 'f' families and every _IOR/_IOW-shaped 'T' request use the _IOC encoding (TIOCGPGRP 0x80047477, TIOCSPGRP 0x40047476, FIONBIO 0x4004667E, FIONREAD 0x8004667F, TCFLSH 0x741F, ...). As a result hush's tcgetpgrp got ENOTTY on Gibux. The __XTENSA__ arms are now computed from Linux 7.0's arch/xtensa/include/uapi/asm/ioctls.h: 37 constants in sys/ioctl.h and 3 in termios.h. TIOCGWINSZ/TIOCSWINSZ were already right."
status: done
owner: unassigned
---

# xtensa tty ioctls used the generic numbers

pxx2 found it running BusyBox hush on Gibux: tcgetpgrp issued ioctl(0, 0x540f).

## Fix
A script parsed the kernel header, expanded _IO/_IOR/_IOW with the generic _IOC layout, which xtensa uses, and wrapped every crtl constant whose xtensa value differs in `#if defined(__XTENSA__)`. The kernel's own literal comments (TCGETA 0x80127417, TIOCGWINSZ 0x80087468) agree with the expansion. crtl's tcflush, tcdrain, tcgetpgrp and tcsetpgrp now issue the xtensa numbers.

## Test
test/c_busybox_hush_gaps.c runs FIONREAD and FIONBIO on a pipe, which needs no terminal, on x86-64 and hosted xtensa, against gcc. The previous runtime on xtensa gives `fionread -1 -1`; before the read was guarded it hung, because the FIONBIO failed and the read blocked.
