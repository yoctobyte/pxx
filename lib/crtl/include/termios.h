/* SPDX-License-Identifier: Zlib */
#ifndef PXX_CRTL_TERMIOS_H
#define PXX_CRTL_TERMIOS_H 1

/* Terminal attributes, over the general PalIoctl bridge — these are REAL, not
   stubs: TCGETS/TCSETS are ordinary ioctls and crtl already has __pxx_ioctl.
   (Same lesson as the note in <sys/ioctl.h>: the claim that a new PAL entry was
   needed there was wrong. Measure before believing a scoping line.)

   *** THE STRUCT BELOW IS THE KERNEL'S, NOT GLIBC'S. ***
   `struct termios` has two layouts on Linux. The kernel's, which TCGETS
   actually reads and writes, has NCCS == 19 and no c_ispeed/c_ospeed; glibc's
   userspace struct has NCCS == 32 and both speed fields, and glibc translates
   between them. crtl has no libc to translate through, so it uses the kernel's
   layout directly and the ioctl needs no fixup at all.

   The consequence, stated rather than left to be discovered: a program built
   entirely by pxx is self-consistent, but a struct termios that crossed into
   glibc code would disagree about its own size (ours is 36 bytes, glibc's is
   60). That is the same hazard the `crtl does not define ...` warning exists
   for.

   *** ONE DELIBERATE DIVERGENCE, in the cf*speed family. *** crtl keeps the
   speed where the kernel keeps it — the CBAUD bits of c_cflag — so there is
   one speed, and cfsetispeed sets it. Modern glibc does something else, and it
   was measured rather than assumed: it carries separate c_ispeed/c_ospeed
   fields, cfgetospeed returns the NUMERIC rate (9600, not B9600 == 0o15), and
   cfsetispeed(B115200) sets a BOTHER encoding in the high c_cflag bits and
   leaves the output speed alone. That is glibc's arbitrary-baud support built
   on termios2, and reproducing it would mean carrying termios2 as well.

   We do not, on the compat ceiling: real code sets both directions to the same
   Bxxx and reads it back, which works here exactly. Split input/output rates
   and non-standard baud rates are NOT supported, and cfgetospeed returns the
   Bxxx code, not the rate. Anything that needs those wants termios2 and should
   say so rather than silently getting the wrong line speed.

   Constants are asm-generic's, which covers every target pxx builds for
   (x86_64, aarch64, arm32, riscv32/64, xtensa); only mips/alpha/sparc/parisc/
   powerpc differ and pxx targets none of them. */

typedef unsigned char  cc_t;
typedef unsigned int   speed_t;
typedef unsigned int   tcflag_t;

#define NCCS 19

struct termios {
  tcflag_t c_iflag;
  tcflag_t c_oflag;
  tcflag_t c_cflag;
  tcflag_t c_lflag;
  cc_t     c_line;
  cc_t     c_cc[NCCS];
};

/* c_cc subscripts */
#define VINTR    0
#define VQUIT    1
#define VERASE   2
#define VKILL    3
#define VEOF     4
#define VTIME    5
#define VMIN     6
#define VSWTC    7
#define VSTART   8
#define VSTOP    9
#define VSUSP   10
#define VEOL    11
#define VREPRINT 12
#define VDISCARD 13
#define VWERASE 14
#define VLNEXT  15
#define VEOL2   16

/* c_iflag */
#define IGNBRK  0000001
#define BRKINT  0000002
#define IGNPAR  0000004
#define PARMRK  0000010
#define INPCK   0000020
#define ISTRIP  0000040
#define INLCR   0000100
#define IGNCR   0000200
#define ICRNL   0000400
#define IUCLC   0001000
#define IXON    0002000
#define IXANY   0004000
#define IXOFF   0010000
#define IMAXBEL 0020000
#define IUTF8   0040000

/* c_oflag */
#define OPOST   0000001
#define OLCUC   0000002
#define ONLCR   0000004
#define OCRNL   0000010
#define ONOCR   0000020
#define ONLRET  0000040
#define OFILL   0000100
#define OFDEL   0000200

/* c_cflag — the baud rate lives in the low bits here, which is why there is no
   c_ispeed field to set. */
#define CBAUD   0010017
#define CBAUDEX 0010000
#define CSIZE   0000060
#define CS5     0000000
#define CS6     0000020
#define CS7     0000040
#define CS8     0000060
#define CSTOPB  0000100
#define CREAD   0000200
#define PARENB  0000400
#define PARODD  0001000
#define HUPCL   0002000
#define CLOCAL  0004000
#define CRTSCTS 020000000000

#define B0      0000000
#define B50     0000001
#define B75     0000002
#define B110    0000003
#define B134    0000004
#define B150    0000005
#define B200    0000006
#define B300    0000007
#define B600    0000010
#define B1200   0000011
#define B1800   0000012
#define B2400   0000013
#define B4800   0000014
#define B9600   0000015
#define B19200  0000016
#define B38400  0000017
#define B57600  0010001
#define B115200 0010002
#define B230400 0010003

/* c_lflag */
#define ISIG    0000001
#define ICANON  0000002
#define XCASE   0000004
#define ECHO    0000010
#define ECHOE   0000020
#define ECHOK   0000040
#define ECHONL  0000100
#define NOFLSH  0000200
#define TOSTOP  0000400
#define ECHOCTL 0001000
#define ECHOPRT 0002000
#define ECHOKE  0004000
#define FLUSHO  0010000
#define PENDIN  0040000
#define IEXTEN  0100000
#define EXTPROC 0200000

/* tcsetattr actions, and tcflush queues */
#define TCSANOW   0
#define TCSADRAIN 1
#define TCSAFLUSH 2

#define TCIFLUSH  0
#define TCOFLUSH  1
#define TCIOFLUSH 2

/* tcflow actions */
#define TCOOFF 0
#define TCOON  1
#define TCIOFF 2
#define TCION  3

struct winsize {
  unsigned short ws_row;
  unsigned short ws_col;
  unsigned short ws_xpixel;
  unsigned short ws_ypixel;
};

#define TIOCGWINSZ 0x5413
#define TIOCSWINSZ 0x5414

int tcgetattr(int fd, struct termios *t);
int tcsetattr(int fd, int actions, const struct termios *t);
int tcflush(int fd, int queue);
int tcdrain(int fd);
int tcflow(int fd, int action);
int tcsendbreak(int fd, int duration);

/* One speed, both directions — see the divergence note at the top. */
speed_t cfgetispeed(const struct termios *t);
speed_t cfgetospeed(const struct termios *t);
int cfsetispeed(struct termios *t, speed_t speed);
int cfsetospeed(struct termios *t, speed_t speed);
int cfsetspeed(struct termios *t, speed_t speed);
void cfmakeraw(struct termios *t);

#endif
