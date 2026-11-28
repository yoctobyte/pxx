/* __LINE__ inside a function-like macro invocation that spans lines: gcc and
   clang give the line of the macro NAME (the invocation's start); pxx gave
   the line of its closing parenthesis. Every multi-line log macro showed it
   (wlroots' wlr_log_errno: sockets.c:49 against gcc's :47).
   bug-c-line-in-a-multi-line-macro-call-is-its-last-line */
#include <stdio.h>
#define LOG(fmt, ...) printf("[%d] " fmt "\n", __LINE__, ##__VA_ARGS__)
#define LOGE(fmt, ...) LOG(fmt " e", ##__VA_ARGS__)
#define HERE __LINE__
#define PAIR(a, b) printf("pair %d %d\n", a, b)
#define ID(x) x
static int f(int a, int b) { return a * 1000 + b; }
int main(void) {
  LOG("one");
  LOG("two %d",
      2);
  LOGE("three %d",
      3,
      4);
  PAIR(__LINE__,
       __LINE__);
  PAIR(HERE,
       HERE);
  LOG
     ("name and paren on different lines");
  printf("plain call %d\n", f(__LINE__,
                              __LINE__));
  printf("id %d\n", ID(
      ID(__LINE__)));
  LOG("after %d", 1); LOG("same line %d",
      2);
  printf("last %d\n", __LINE__);
  return 0;
}
