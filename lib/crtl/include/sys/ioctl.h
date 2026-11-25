/* SPDX-License-Identifier: Zlib */
#ifndef PXX_CRTL_SYS_IOCTL_H
#define PXX_CRTL_SYS_IOCTL_H 1

/* Minimal ioctl surface (sqlite's unix VFS wants the declaration). Implemented
   in src/sys/ioctl.c over the general PalIoctl syscall bridge. */

extern int ioctl(int fd, unsigned long request, ...);
extern int __pxx_ioctl(int fd, long request, void *argp);

/* TCGETS is 0x5401 on every target pxx builds for (asm-generic/ioctls.h; only
   mips/alpha/sparc/powerpc differ) — the same constant __pxx_isatty uses. */
#define TCGETS  0x5401
#if defined(__XTENSA__)
#define FIONREAD 0x8004667F
#else
#define FIONREAD 0x541B
#endif

/* THE TTY IOCTLS, script-transcribed from this box's
   /usr/include/asm-generic/ioctls.h -- the same discipline as the socket block
   above and for the same reason: TIOCSCTTY was reaching busybox's init as an
   UNDECLARED IDENTIFIER TREATED AS 0, and ioctl(fd, 0, ...) is not a failure,
   it is a different call. A tty number recalled one digit wrong does not error
   either.

   ARCHITECTURE CAVEAT, and it is real where the socket block's is not: these
   numbers are asm-generic's, which x86, arm, arm64 and riscv use unchanged.
   XTENSA DOES NOT: its asm/ioctls.h keeps TCGETS..TCSETSF and the plain 'T'
   _IO numbers, but the 't'/'f' families and every _IOR/_IOW-shaped 'T'
   request carry the _IOC encoding (TIOCGPGRP 0x80047477, FIONBIO
   0x4004667E). The __XTENSA__ arms below were computed from Linux 7.0's
   arch/xtensa/include/uapi/asm/ioctls.h; hush's tcgetpgrp got ENOTTY on Nilix
   with 0x540F. bug-crtl-xtensa-tty-ioctls-use-the-generic-numbers.
   mips, alpha, sparc and powerpc differ again; pxx builds for none of them.

   The _IOR/_IOW-shaped entries in that header (TCGETS2, TIOCGPTPEER, the
   TIOCGRS485 pair, ...) are deliberately NOT here: transcribing their expansion
   would bake in this box's _IOC layout, and a program that wants them can spell
   the macro itself. Only the plain numeric constants are copied. */
#define TCSETS             0x5402
#define TCSETSW            0x5403
#define TCSETSF            0x5404
#if defined(__XTENSA__)
#define TCGETA             0x80127417
#else
#define TCGETA             0x5405
#endif
#if defined(__XTENSA__)
#define TCSETA             0x40127418
#else
#define TCSETA             0x5406
#endif
#if defined(__XTENSA__)
#define TCSETAW            0x40127419
#else
#define TCSETAW            0x5407
#endif
#if defined(__XTENSA__)
#define TCSETAF            0x4012741C
#else
#define TCSETAF            0x5408
#endif
#if defined(__XTENSA__)
#define TCSBRK             0x741D
#else
#define TCSBRK             0x5409
#endif
#if defined(__XTENSA__)
#define TCXONC             0x741E
#else
#define TCXONC             0x540A
#endif
#if defined(__XTENSA__)
#define TCFLSH             0x741F
#else
#define TCFLSH             0x540B
#endif
#define TIOCEXCL           0x540C
#define TIOCNXCL           0x540D
#define TIOCSCTTY          0x540E
#if defined(__XTENSA__)
#define TIOCGPGRP          0x80047477
#else
#define TIOCGPGRP          0x540F
#endif
#if defined(__XTENSA__)
#define TIOCSPGRP          0x40047476
#else
#define TIOCSPGRP          0x5410
#endif
#if defined(__XTENSA__)
#define TIOCOUTQ           0x80047473
#else
#define TIOCOUTQ           0x5411
#endif
#if defined(__XTENSA__)
#define TIOCSTI            0x40015412
#else
#define TIOCSTI            0x5412
#endif
/* glibc's <sys/ioctl.h> provides this (via bits/ioctl-types.h) and ours did
   not, so `#include <sys/ioctl.h>` followed by `struct winsize ws;` -- the
   canonical way C code asks for the terminal size -- got an INCOMPLETE TYPE.
   pxx's C frontend accepts that silently today and reads garbage from it
   (gcc: "storage size of 'ws' isn't known"), filed separately as
   bug-c-an-undeclared-struct-type-compiles-and-reads-garbage; declaring the
   struct here is the right fix regardless of what that frontend bug does. */
#ifndef __struct_winsize_defined
#define __struct_winsize_defined 1
struct winsize {
  unsigned short ws_row;
  unsigned short ws_col;
  unsigned short ws_xpixel;
  unsigned short ws_ypixel;
};
#endif

/* Conditional for the same measured reason as the copy in <termios.h>, which
   carries the full note: xtensa keeps the BSD-style 't' encoding for the
   window-size family while using asm-generic for TCGETS/TCSETS, and Linux's
   _IOR sets 0x80000000 where BSD's sets 0x40000000. Both headers must agree --
   a program that includes either one gets the constant.
   bug-b-terminalsize-answers-enotty-on-xtensa-and-the-probe-cannot-say-why */
#if defined(__XTENSA__)
#define TIOCGWINSZ         0x80087468
#define TIOCSWINSZ         0x40087467
#else
#define TIOCGWINSZ         0x5413
#define TIOCSWINSZ         0x5414
#endif
#if defined(__XTENSA__)
#define TIOCMGET           0x80045415
#else
#define TIOCMGET           0x5415
#endif
#if defined(__XTENSA__)
#define TIOCMBIS           0x40045416
#else
#define TIOCMBIS           0x5416
#endif
#if defined(__XTENSA__)
#define TIOCMBIC           0x40045417
#else
#define TIOCMBIC           0x5417
#endif
#if defined(__XTENSA__)
#define TIOCMSET           0x40045418
#else
#define TIOCMSET           0x5418
#endif
#if defined(__XTENSA__)
#define TIOCGSOFTCAR       0x80045419
#else
#define TIOCGSOFTCAR       0x5419
#endif
#if defined(__XTENSA__)
#define TIOCSSOFTCAR       0x4004541A
#else
#define TIOCSSOFTCAR       0x541A
#endif
#if defined(__XTENSA__)
#define TIOCLINUX          0x4001541C
#else
#define TIOCLINUX          0x541C
#endif
#define TIOCCONS           0x541D
#if defined(__XTENSA__)
#define TIOCGSERIAL        0x803C541E
#else
#define TIOCGSERIAL        0x541E
#endif
#if defined(__XTENSA__)
#define TIOCSSERIAL        0x403C541F
#else
#define TIOCSSERIAL        0x541F
#endif
#if defined(__XTENSA__)
#define TIOCPKT            0x40045420
#else
#define TIOCPKT            0x5420
#endif
#if defined(__XTENSA__)
#define FIONBIO            0x4004667E
#else
#define FIONBIO            0x5421
#endif
#define TIOCNOTTY          0x5422
#if defined(__XTENSA__)
#define TIOCSETD           0x40045423
#else
#define TIOCSETD           0x5423
#endif
#if defined(__XTENSA__)
#define TIOCGETD           0x80045424
#else
#define TIOCGETD           0x5424
#endif
#if defined(__XTENSA__)
#define TCSBRKP            0x40045425
#else
#define TCSBRKP            0x5425     /* Needed for POSIX tcsendbreak() */
#endif
#define TIOCSBRK           0x5427     /* BSD compatibility */
#define TIOCCBRK           0x5428     /* BSD compatibility */
#if defined(__XTENSA__)
#define TIOCGSID           0x80045429
#else
#define TIOCGSID           0x5429     /* Return the session ID of FD */
#endif
#if defined(__XTENSA__)
#define TIOCGRS485         0x8020542E
#else
#define TIOCGRS485         0x542E
#endif
#if defined(__XTENSA__)
#define TIOCSRS485         0xC020542F
#else
#define TIOCSRS485         0x542F
#endif
#define TCGETX             0x5432     /* SYS5 TCGETX compatibility */
#define TCSETX             0x5433
#define TCSETXF            0x5434
#define TCSETXW            0x5435
#define TIOCVHANGUP        0x5437
#if defined(__XTENSA__)
#define FIONCLEX           0x6602
#else
#define FIONCLEX           0x5450
#endif
#if defined(__XTENSA__)
#define FIOCLEX            0x6601
#else
#define FIOCLEX            0x5451
#endif
#if defined(__XTENSA__)
#define FIOASYNC           0x4004667D
#else
#define FIOASYNC           0x5452
#endif
#define TIOCSERCONFIG      0x5453
#if defined(__XTENSA__)
#define TIOCSERGWILD       0x80045454
#else
#define TIOCSERGWILD       0x5454
#endif
#if defined(__XTENSA__)
#define TIOCSERSWILD       0x40045455
#else
#define TIOCSERSWILD       0x5455
#endif
#define TIOCGLCKTRMIOS     0x5456
#define TIOCSLCKTRMIOS     0x5457
#define TIOCSERGSTRUCT     0x5458     /* For debugging only */
#if defined(__XTENSA__)
#define TIOCSERGETLSR      0x80045459
#else
#define TIOCSERGETLSR      0x5459     /* Get line status register */
#endif
#if defined(__XTENSA__)
#define TIOCSERGETMULTI    0x80A8545A
#else
#define TIOCSERGETMULTI    0x545A     /* Get multiport config */
#endif
#if defined(__XTENSA__)
#define TIOCSERSETMULTI    0x40A8545B
#else
#define TIOCSERSETMULTI    0x545B     /* Set multiport config */
#endif
#define TIOCMIWAIT         0x545C     /* wait for a change on serial input line(s) */
#define TIOCGICOUNT        0x545D     /* read serial port __inline__ interrupt counts */
#define TIOCPKT_DATA       0
#define TIOCPKT_FLUSHREAD  1
#define TIOCPKT_FLUSHWRITE 2
#define TIOCPKT_STOP       4
#define TIOCPKT_START      8
#define TIOCPKT_NOSTOP     16
#define TIOCPKT_DOSTOP     32
#define TIOCPKT_IOCTL      64
#define TIOCSER_TEMT       0x01     /* Transmitter physically empty */

/* THE LINE DISCIPLINES, transcribed from this box's
   /usr/include/x86_64-linux-gnu/bits/ioctl-types.h (lines 51-65). They live in
   <sys/ioctl.h> because that is the header glibc reaches them through, and
   because TIOCSETD/TIOCGETD above are the only calls that take one -- a
   constant and the ioctl that consumes it belong in the same place.

   These are the kernel's numbers and are architecture-independent, like the
   socket ioctls below and unlike the tty ioctls above.

   Found attempting busybox at 394 applets: networking/slattach.c:107 is
   `static const int int_N_SLIP = N_SLIP;', which it then hands to
   ioctl(fd, TIOCSETD, &int_N_SLIP). Before `a157e88ee' that was the discipline
   number 0 -- N_TTY -- so slattach installed the ordinary terminal discipline
   and reported success, which is a SLIP interface that carries nothing. */
#define N_TTY           0
#define N_SLIP          1
#define N_MOUSE         2
#define N_PPP           3
#define N_STRIP         4
#define N_AX25          5
#define N_X25           6     /* X.25 async */
#define N_6PACK         7
#define N_MASC          8     /* Mobitex module */
#define N_R3964         9     /* Simatic R3964 module */
#define N_PROFIBUS_FDL  10    /* Profibus */
#define N_IRDA          11    /* Linux IR */
#define N_SMSBLOCK      12    /* SMS block mode */
#define N_HDLC          13    /* synchronous HDLC */
#define N_SYNC_PPP      14    /* synchronous PPP */

/* THE MODEM STATUS BITS, from the same header (lines 36-46). They are the
   argument TIOCMGET reads into and TIOCMSET/TIOCMBIC/TIOCMBIS write, all three
   of which are already above -- so this is the same shape as the line
   disciplines: the ioctls were here and the numbers they carry were not.

   TIOCM_CD and TIOCM_RI are aliases and not extra bits; glibc spells them as
   aliases and so does this, because a program that tests carrier detect writes
   one name and a program that tests ring writes the other, and collapsing them
   to literals loses which question was being asked.

   Found attempting busybox at 394 applets, on the SECOND pass: closing N_SLIP
   moved networking/slattach.c's refusal from :107 to :218, where it polls
   carrier with `ioctl(fd, TIOCMGET, &modem) ... modem & TIOCM_CAR'. At 0 that
   is carrier permanently absent. A first-error-per-TU census names the first
   wall in a file, never every wall -- this constant was invisible until the
   one in front of it was gone. */
#define TIOCM_LE        0x001
#define TIOCM_DTR       0x002
#define TIOCM_RTS       0x004
#define TIOCM_ST        0x008
#define TIOCM_SR        0x010
#define TIOCM_CTS       0x020
#define TIOCM_CAR       0x040
#define TIOCM_RNG       0x080
#define TIOCM_DSR       0x100
#define TIOCM_CD        TIOCM_CAR
#define TIOCM_RI        TIOCM_RNG

/* THE SOCKET IOCTLS, transcribed from this box's /usr/include/linux/sockios.h
   by a script rather than by hand -- 77 numbers is exactly the population where
   one recalled digit becomes a DIFFERENT ioctl on a real socket, and a wrong
   SIOCGIF* does not fail: it fills a different part of `struct ifreq' and the
   caller prints a plausible address. They live in <sys/ioctl.h> because that is
   where glibc puts them (via bits/ioctls.h -> linux/sockios.h) and therefore
   where every program looks; <net/if.h> supplies the struct they operate on.

   These are architecture-independent in the kernel -- unlike the tty ioctls
   above, sockios.h has no per-arch variant at all.

   Found attempting busybox rung 2: networking/ifconfig.c, route.c, arp.c,
   libbb/xconnect.c. SIOCGIWAP and the wireless set are NOT here; they belong to
   linux/wireless.h, which a program that wants them includes itself.
   SIOCSKEEPALIVE/SIOCSOUTFILL are likewise linux/if_slip.h's, defined there in
   terms of SIOCDEVPRIVATE below. */
#define SIOCADDRT                0x890B     /* add routing table entry	*/
#define SIOCDELRT                0x890C     /* delete routing table entry	*/
#define SIOCRTMSG                0x890D     /* unused			*/
#define SIOCGIFNAME              0x8910     /* get iface name		*/
#define SIOCSIFLINK              0x8911     /* set iface channel		*/
#define SIOCGIFCONF              0x8912     /* get iface list		*/
#define SIOCGIFFLAGS             0x8913     /* get flags			*/
#define SIOCSIFFLAGS             0x8914     /* set flags			*/
#define SIOCGIFADDR              0x8915     /* get PA address		*/
#define SIOCSIFADDR              0x8916     /* set PA address		*/
#define SIOCGIFDSTADDR           0x8917     /* get remote PA address	*/
#define SIOCSIFDSTADDR           0x8918     /* set remote PA address	*/
#define SIOCGIFBRDADDR           0x8919     /* get broadcast PA address	*/
#define SIOCSIFBRDADDR           0x891a     /* set broadcast PA address	*/
#define SIOCGIFNETMASK           0x891b     /* get network PA mask		*/
#define SIOCSIFNETMASK           0x891c     /* set network PA mask		*/
#define SIOCGIFMETRIC            0x891d     /* get metric			*/
#define SIOCSIFMETRIC            0x891e     /* set metric			*/
#define SIOCGIFMEM               0x891f     /* get memory address (BSD)	*/
#define SIOCSIFMEM               0x8920     /* set memory address (BSD)	*/
#define SIOCGIFMTU               0x8921     /* get MTU size			*/
#define SIOCSIFMTU               0x8922     /* set MTU size			*/
#define SIOCSIFNAME              0x8923     /* set interface name */
#define SIOCSIFHWADDR            0x8924     /* set hardware address 	*/
#define SIOCGIFENCAP             0x8925     /* get/set encapsulations       */
#define SIOCSIFENCAP             0x8926     
#define SIOCGIFHWADDR            0x8927     /* Get hardware address		*/
#define SIOCGIFSLAVE             0x8929     /* Driver slaving support	*/
#define SIOCSIFSLAVE             0x8930     
#define SIOCADDMULTI             0x8931     /* Multicast address lists	*/
#define SIOCDELMULTI             0x8932     
#define SIOCGIFINDEX             0x8933     /* name -> if_index mapping	*/
#define SIOGIFINDEX              SIOCGIFINDEX /* misprint compatibility :-)	*/
#define SIOCSIFPFLAGS            0x8934     /* set/get extended flags set	*/
#define SIOCGIFPFLAGS            0x8935     
#define SIOCDIFADDR              0x8936     /* delete PA address		*/
#define SIOCSIFHWBROADCAST       0x8937     /* set hardware broadcast addr	*/
#define SIOCGIFCOUNT             0x8938     /* get number of devices */
#define SIOCGIFBR                0x8940     /* Bridging support		*/
#define SIOCSIFBR                0x8941     /* Set bridging options 	*/
#define SIOCGIFTXQLEN            0x8942     /* Get the tx queue length	*/
#define SIOCSIFTXQLEN            0x8943     /* Set the tx queue length 	*/
#define SIOCETHTOOL              0x8946     /* Ethtool interface		*/
#define SIOCGMIIPHY              0x8947     /* Get address of MII PHY in use. */
#define SIOCGMIIREG              0x8948     /* Read MII PHY register.	*/
#define SIOCSMIIREG              0x8949     /* Write MII PHY register.	*/
#define SIOCWANDEV               0x894A     /* get/set netdev parameters	*/
#define SIOCOUTQNSD              0x894B     /* output queue size (not sent only) */
#define SIOCGSKNS                0x894C     /* get socket network namespace */
#define SIOCDARP                 0x8953     /* delete ARP table entry	*/
#define SIOCGARP                 0x8954     /* get ARP table entry		*/
#define SIOCSARP                 0x8955     /* set ARP table entry		*/
#define SIOCDRARP                0x8960     /* delete RARP table entry	*/
#define SIOCGRARP                0x8961     /* get RARP table entry		*/
#define SIOCSRARP                0x8962     /* set RARP table entry		*/
#define SIOCGIFMAP               0x8970     /* Get device parameters	*/
#define SIOCSIFMAP               0x8971     /* Set device parameters	*/
#define SIOCADDDLCI              0x8980     /* Create new DLCI device	*/
#define SIOCDELDLCI              0x8981     /* Delete DLCI device		*/
#define SIOCGIFVLAN              0x8982     /* 802.1Q VLAN support		*/
#define SIOCSIFVLAN              0x8983     /* Set 802.1Q VLAN options 	*/
#define SIOCBONDENSLAVE          0x8990     /* enslave a device to the bond */
#define SIOCBONDRELEASE          0x8991     /* release a slave from the bond*/
#define SIOCBONDSETHWADDR        0x8992     /* set the hw addr of the bond  */
#define SIOCBONDSLAVEINFOQUERY   0x8993     /* rtn info about slave state   */
#define SIOCBONDINFOQUERY        0x8994     /* rtn info about bond state    */
#define SIOCBONDCHANGEACTIVE     0x8995     /* update to a new active slave */
#define SIOCBRADDBR              0x89a0     /* create new bridge device     */
#define SIOCBRDELBR              0x89a1     /* remove bridge device         */
#define SIOCBRADDIF              0x89a2     /* add interface to bridge      */
#define SIOCBRDELIF              0x89a3     /* remove interface from bridge */
#define SIOCSHWTSTAMP            0x89b0     /* set and get config		*/
#define SIOCGHWTSTAMP            0x89b1     /* get config			*/
#define SIOCDEVPRIVATE           0x89F0     /* to 89FF */
#define SIOCPROTOPRIVATE         0x89E0     /* to 89EF */

/* The _IOC request-encoding family lives in <asm-generic/ioctl.h>, where
   the UAPI headers (drm.h, via <asm/ioctl.h>) look for it too. */
#include <asm-generic/ioctl.h>

/* The two pty ioctls, SPELLED WITH THE MACROS ABOVE RATHER THAN AS NUMBERS.
   The tty block near the top of this file says the _IOR/_IOW-shaped entries are
   deliberately absent because "transcribing their expansion would bake in this
   box's _IOC layout". These two are that shape, and this is not a reversal of
   that rule -- it is the rule's own remedy: written as _IOW/_IOR they carry the
   layout from the definitions above instead of a constant measured on one
   machine, so a target that encoded differently would produce a different (and
   correct) value rather than silently inheriting x86-64's.

   Verified against glibc on this box: TIOCSPTLCK expands to 0x40045431 and
   TIOCGPTN to 0x80045430, which is what <asm/ioctls.h> gives. That check is
   what makes the spelling above a claim rather than a hope, and it is a real
   check because a wrong _IOC layout produces a number, not an error.

   They live here and not in the numeric block because they are computed; a
   reader scanning the numeric list for them will not find one, which is the
   point. feature-c-crtl-has-no-pty-family-at-all */
#define TIOCGPTN    _IOR('T', 0x30, unsigned int)
#define TIOCSPTLCK  _IOW('T', 0x31, int)


#endif
