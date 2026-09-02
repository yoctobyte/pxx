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
#define FIONREAD 0x541B

/* THE TTY IOCTLS, script-transcribed from this box's
   /usr/include/asm-generic/ioctls.h -- the same discipline as the socket block
   above and for the same reason: TIOCSCTTY was reaching busybox's init as an
   UNDECLARED IDENTIFIER TREATED AS 0, and ioctl(fd, 0, ...) is not a failure,
   it is a different call. A tty number recalled one digit wrong does not error
   either.

   ARCHITECTURE CAVEAT, and it is real where the socket block's is not: these
   numbers are asm-generic's, which x86, arm, arm64, riscv and xtensa all use
   unchanged -- but mips, alpha, sparc and powerpc define their own. pxx builds
   for none of those today. If a target from that set is ever added, this block
   is one of the places that must fork per-arch; the socket ioctls above never
   need to.

   The _IOR/_IOW-shaped entries in that header (TCGETS2, TIOCGPTPEER, the
   TIOCGRS485 pair, ...) are deliberately NOT here: transcribing their expansion
   would bake in this box's _IOC layout, and a program that wants them can spell
   the macro itself. Only the plain numeric constants are copied. */
#define TCSETS             0x5402
#define TCSETSW            0x5403
#define TCSETSF            0x5404
#define TCGETA             0x5405
#define TCSETA             0x5406
#define TCSETAW            0x5407
#define TCSETAF            0x5408
#define TCSBRK             0x5409
#define TCXONC             0x540A
#define TCFLSH             0x540B
#define TIOCEXCL           0x540C
#define TIOCNXCL           0x540D
#define TIOCSCTTY          0x540E
#define TIOCGPGRP          0x540F
#define TIOCSPGRP          0x5410
#define TIOCOUTQ           0x5411
#define TIOCSTI            0x5412
#define TIOCGWINSZ         0x5413
#define TIOCSWINSZ         0x5414
#define TIOCMGET           0x5415
#define TIOCMBIS           0x5416
#define TIOCMBIC           0x5417
#define TIOCMSET           0x5418
#define TIOCGSOFTCAR       0x5419
#define TIOCSSOFTCAR       0x541A
#define TIOCLINUX          0x541C
#define TIOCCONS           0x541D
#define TIOCGSERIAL        0x541E
#define TIOCSSERIAL        0x541F
#define TIOCPKT            0x5420
#define FIONBIO            0x5421
#define TIOCNOTTY          0x5422
#define TIOCSETD           0x5423
#define TIOCGETD           0x5424
#define TCSBRKP            0x5425     /* Needed for POSIX tcsendbreak() */
#define TIOCSBRK           0x5427     /* BSD compatibility */
#define TIOCCBRK           0x5428     /* BSD compatibility */
#define TIOCGSID           0x5429     /* Return the session ID of FD */
#define TIOCGRS485         0x542E
#define TIOCSRS485         0x542F
#define TCGETX             0x5432     /* SYS5 TCGETX compatibility */
#define TCSETX             0x5433
#define TCSETXF            0x5434
#define TCSETXW            0x5435
#define TIOCVHANGUP        0x5437
#define FIONCLEX           0x5450
#define FIOCLEX            0x5451
#define FIOASYNC           0x5452
#define TIOCSERCONFIG      0x5453
#define TIOCSERGWILD       0x5454
#define TIOCSERSWILD       0x5455
#define TIOCGLCKTRMIOS     0x5456
#define TIOCSLCKTRMIOS     0x5457
#define TIOCSERGSTRUCT     0x5458     /* For debugging only */
#define TIOCSERGETLSR      0x5459     /* Get line status register */
#define TIOCSERGETMULTI    0x545A     /* Get multiport config */
#define TIOCSERSETMULTI    0x545B     /* Set multiport config */
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

/* The _IOC request-encoding family (asm-generic/ioctl.h). glibc's <sys/ioctl.h>
   reaches these through <bits/ioctls.h> -> <asm/ioctl.h>, and real programs
   spell their own ioctl numbers with them rather than including a linux/ uapi
   header: busybox writes `#define FDGETPRM _IOR(2, 0x04, struct floppy_struct)`
   and `_IOW(BTRFS_IOCTL_MAGIC, 9, int)` directly. Without them the macro name
   survives preprocessing as a call with a TYPE for an argument, which is not a
   C expression at all — the diagnostic lands on `_IOR`, far from the header
   that should have supplied it.

   The layout below is asm-generic's, which every target pxx builds for
   (x86_64, aarch64, arm32, riscv32/64, xtensa) uses; only mips, alpha, sparc,
   parisc and powerpc encode differently, and pxx targets none of them. This is
   the same reasoning the TCGETS constant above rests on.

   _IOC_TYPECHECK is the USER-SPACE spelling: the kernel's variant compares
   sizeof(t) against sizeof(t[1]) to provoke an error when t is not a type, but
   that arm is #ifdef __KERNEL__ and yields the identical value here. */

#include <stddef.h>

#define _IOC_NRBITS    8
#define _IOC_TYPEBITS  8
#define _IOC_SIZEBITS  14
#define _IOC_DIRBITS   2

#define _IOC_NRMASK    ((1 << _IOC_NRBITS) - 1)
#define _IOC_TYPEMASK  ((1 << _IOC_TYPEBITS) - 1)
#define _IOC_SIZEMASK  ((1 << _IOC_SIZEBITS) - 1)
#define _IOC_DIRMASK   ((1 << _IOC_DIRBITS) - 1)

#define _IOC_NRSHIFT   0
#define _IOC_TYPESHIFT (_IOC_NRSHIFT + _IOC_NRBITS)
#define _IOC_SIZESHIFT (_IOC_TYPESHIFT + _IOC_TYPEBITS)
#define _IOC_DIRSHIFT  (_IOC_SIZESHIFT + _IOC_SIZEBITS)

/* Direction is from the APPLICATION's point of view: _IOC_READ means the
   application reads a value the driver wrote. */
#define _IOC_NONE   0U
#define _IOC_WRITE  1U
#define _IOC_READ   2U

#define _IOC(dir, type, nr, size) \
  ((((unsigned int)(dir))  << _IOC_DIRSHIFT)  | \
   (((unsigned int)(type)) << _IOC_TYPESHIFT) | \
   (((unsigned int)(nr))   << _IOC_NRSHIFT)   | \
   (((unsigned int)(size)) << _IOC_SIZESHIFT))

#define _IOC_TYPECHECK(t) (sizeof(t))

#define _IO(type, nr)         _IOC(_IOC_NONE, (type), (nr), 0)
#define _IOR(type, nr, size)  _IOC(_IOC_READ, (type), (nr), (_IOC_TYPECHECK(size)))
#define _IOW(type, nr, size)  _IOC(_IOC_WRITE, (type), (nr), (_IOC_TYPECHECK(size)))
#define _IOWR(type, nr, size) \
  _IOC(_IOC_READ | _IOC_WRITE, (type), (nr), (_IOC_TYPECHECK(size)))

/* Decoding, for code that inspects a request it was handed. */
#define _IOC_DIR(nr)   (((nr) >> _IOC_DIRSHIFT)  & _IOC_DIRMASK)
#define _IOC_TYPE(nr)  (((nr) >> _IOC_TYPESHIFT) & _IOC_TYPEMASK)
#define _IOC_NR(nr)    (((nr) >> _IOC_NRSHIFT)   & _IOC_NRMASK)
#define _IOC_SIZE(nr)  (((nr) >> _IOC_SIZESHIFT) & _IOC_SIZEMASK)

#endif
