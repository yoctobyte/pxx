/* termios on a pty under --os=freebsd: TCGETS/TCSETS* translate the flag
   words, c_cc indices and line speed (they differ in almost every bit), plus
   TCFLSH and TCSBRK-drain. Run by `make test-freebsd` under script(1) on both
   kernels; output must match. feature-port-freebsd-native */
#include <stdio.h>
#include <termios.h>
#include <unistd.h>
int main(void) {
  struct termios t, r, o;
  if (tcgetattr(0, &o) != 0) { printf("no tty\n"); return 1; }
  printf("canon=%d echo=%d isig=%d icrnl=%d opost=%d onlcr=%d cs8=%d cread=%d\n",
         !!(o.c_lflag & ICANON), !!(o.c_lflag & ECHO), !!(o.c_lflag & ISIG),
         !!(o.c_iflag & ICRNL), !!(o.c_oflag & OPOST), !!(o.c_oflag & ONLCR),
         (o.c_cflag & CSIZE) == CS8, !!(o.c_cflag & CREAD));
  printf("intr=%d eof=%d erase=%d\n", o.c_cc[VINTR], o.c_cc[VEOF], o.c_cc[VERASE]);
  t = o;
  t.c_lflag &= ~(ICANON | ECHO | ISIG | IEXTEN);
  t.c_iflag &= ~(ICRNL | IXON);
  t.c_oflag &= ~OPOST;
  t.c_cc[VMIN] = 3; t.c_cc[VTIME] = 7;
  printf("set=%d\n", tcsetattr(0, TCSANOW, &t));
  tcgetattr(0, &r);
  printf("canon=%d echo=%d isig=%d iexten=%d icrnl=%d ixon=%d opost=%d vmin=%d vtime=%d speed=%d\n",
         !!(r.c_lflag & ICANON), !!(r.c_lflag & ECHO), !!(r.c_lflag & ISIG), !!(r.c_lflag & IEXTEN),
         !!(r.c_iflag & ICRNL), !!(r.c_iflag & IXON), !!(r.c_oflag & OPOST),
         r.c_cc[VMIN], r.c_cc[VTIME], cfgetospeed(&r) == cfgetospeed(&o));
  printf("restore=%d flush=%d drain=%d\n", tcsetattr(0, TCSAFLUSH, &o), tcflush(0, TCIFLUSH), tcdrain(1));
  tcgetattr(0, &r);
  printf("canon=%d echo=%d\n", !!(r.c_lflag & ICANON), !!(r.c_lflag & ECHO));
  return 0;
}
