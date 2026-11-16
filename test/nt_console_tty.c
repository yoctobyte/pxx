/* The Windows console as a terminal (compiler/builtin/winabi.pas,
   ConIoctl): run in a pty under Wine, isatty, TIOCGWINSZ,
   tcgetattr/tcsetattr and a raw-mode read must answer as the Linux build
   does in the same pty (test-windows; escape sequences and CRs are
   stripped, since Wine's console redraws with its own). Before, isatty was
   0 on a console and raw mode never engaged. ReactOS's console, which
   needs the VT emulation (ConWriteVT), is checked by hand with
   tools/vm/reactos/rosinter.sh and the demos from tools/build_nt_demos.sh. */
#include <stdio.h>
#include <unistd.h>
#include <termios.h>
#include <sys/ioctl.h>

int main(void) {
  struct winsize ws;
  struct termios t, raw;
  int r;
  char c = 0;
  printf("isatty %d %d\n", isatty(0), isatty(1));
  r = ioctl(1, TIOCGWINSZ, &ws);
  printf("winsz %d %dx%d\n", r, r == 0 ? ws.ws_col : 0, r == 0 ? ws.ws_row : 0);
  r = tcgetattr(0, &t);
  printf("tcgetattr %d icanon %d echo %d\n", r, (t.c_lflag & ICANON) != 0, (t.c_lflag & ECHO) != 0);
  raw = t;
  raw.c_lflag &= ~(ICANON | ECHO);
  raw.c_cc[VMIN] = 1;
  r = tcsetattr(0, TCSANOW, &raw);
  printf("tcsetattr %d\n", r);
  fflush(stdout);
  r = read(0, &c, 1);
  tcsetattr(0, TCSANOW, &t);
  printf("read %d %d\n", r, c);
  printf("\033[1;31mred\033[0m done\n");
  return 0;
}
