/* SPDX-License-Identifier: Zlib */
/*
 * C runtime: termios — REAL, over the general PalIoctl bridge. TCGETS/TCSETS
 * are ordinary ioctls and crtl already has __pxx_ioctl, so nothing here is a
 * stub. The struct is the KERNEL's layout (NCCS 19, no c_ispeed/c_ospeed), so
 * it goes to the syscall untranslated; see the note in <termios.h> for what
 * that means and does not mean.
 */

#include <termios.h>
#include <errno.h>

extern int __pxx_ioctl(int fd, long request, void *argp);

#define TCGETS_  0x5401
#define TCSETS_  0x5402
#define TCSETSW_ 0x5403
#define TCSETSF_ 0x5404
#define TCSBRK_  0x5409
#define TCXONC_  0x540A
#define TCFLSH_  0x540B

static int tio_ret(int rc) {
  if (rc < 0) { errno = -rc; return -1; }
  return 0;
}

int tcgetattr(int fd, struct termios *t) {
  return tio_ret(__pxx_ioctl(fd, TCGETS_, t));
}

/* The three actions differ only in WHEN the change takes effect, and the
   kernel encodes that as three request numbers rather than an argument — so
   the mapping is the whole implementation. An unknown action is EINVAL, not a
   silent TCSANOW: "applied sooner than you asked" is the kind of wrong answer
   that shows up as a lost keystroke much later. */
int tcsetattr(int fd, int actions, const struct termios *t) {
  long req;
  if (actions == TCSANOW)        req = TCSETS_;
  else if (actions == TCSADRAIN) req = TCSETSW_;
  else if (actions == TCSAFLUSH) req = TCSETSF_;
  else { errno = EINVAL; return -1; }
  return tio_ret(__pxx_ioctl(fd, req, (void *)t));
}

/* TCFLSH/TCXONC/TCSBRK take their argument as the VALUE of the third syscall
   parameter, not as a pointer to it — which is why these cast rather than
   pass &arg. Getting that backwards reads the queue selector out of a stack
   address and flushes the wrong queue. */
int tcflush(int fd, int queue) {
  if (queue != TCIFLUSH && queue != TCOFLUSH && queue != TCIOFLUSH) {
    errno = EINVAL; return -1;
  }
  return tio_ret(__pxx_ioctl(fd, TCFLSH_, (void *)(long)queue));
}

int tcflow(int fd, int action) {
  if (action != TCOOFF && action != TCOON && action != TCIOFF && action != TCION) {
    errno = EINVAL; return -1;
  }
  return tio_ret(__pxx_ioctl(fd, TCXONC_, (void *)(long)action));
}

int tcdrain(int fd) {
  /* TCSBRK with a nonzero argument is "wait for output to drain" — the same
     call that sends a break when the argument is 0. */
  return tio_ret(__pxx_ioctl(fd, TCSBRK_, (void *)(long)1));
}

int tcsendbreak(int fd, int duration) {
  (void)duration;   /* Linux ignores it for TCSBRK; glibc does the same */
  return tio_ret(__pxx_ioctl(fd, TCSBRK_, (void *)(long)0));
}

/* Speed lives in the CBAUD bits of c_cflag, where the KERNEL keeps it, so there
   is one speed and both directions read it. That is a deliberate divergence
   from modern glibc, which carries separate c_ispeed/c_ospeed and a termios2
   BOTHER encoding for arbitrary rates — measured, not assumed. The header's
   divergence note has the numbers and the reasoning; the short version is that
   real code sets both directions to the same Bxxx, which works exactly here,
   and split or non-standard rates need termios2 rather than a half-emulation
   that silently picks the wrong line speed. */
speed_t cfgetospeed(const struct termios *t) { return t->c_cflag & CBAUD; }
speed_t cfgetispeed(const struct termios *t) { return t->c_cflag & CBAUD; }

int cfsetospeed(struct termios *t, speed_t speed) {
  if (speed & ~(speed_t)CBAUD) { errno = EINVAL; return -1; }
  t->c_cflag = (t->c_cflag & ~(tcflag_t)CBAUD) | (tcflag_t)speed;
  return 0;
}
int cfsetispeed(struct termios *t, speed_t speed) { return cfsetospeed(t, speed); }
int cfsetspeed(struct termios *t, speed_t speed)  { return cfsetospeed(t, speed); }

/* cfmakeraw: glibc's exact set. Not "clear everything" — ECHO stays off but
   CREAD stays on, and VMIN/VTIME become 1/0 so a read returns on one byte
   rather than blocking for a line. */
void cfmakeraw(struct termios *t) {
  t->c_iflag &= ~(tcflag_t)(IGNBRK | BRKINT | PARMRK | ISTRIP |
                            INLCR | IGNCR | ICRNL | IXON);
  t->c_oflag &= ~(tcflag_t)OPOST;
  t->c_lflag &= ~(tcflag_t)(ECHO | ECHONL | ICANON | ISIG | IEXTEN);
  t->c_cflag &= ~(tcflag_t)(CSIZE | PARENB);
  t->c_cflag |=  (tcflag_t)CS8;
  t->c_cc[VMIN]  = 1;
  t->c_cc[VTIME] = 0;
}
