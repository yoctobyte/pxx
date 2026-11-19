/* On wasm32 every initialised file-scope variable read 0, and a
   constructor never ran: b3c5f711ea moved main's initialisers into a
   hand-emitted __pxx_c_main_init the wasm backend never built, and
   constructors were called with a raw call it never saw. NAN in math.h is a
   static const union, so isnan(NAN) answered 0. Output must equal gcc.
   bug-c-wasm32-file-scope-initialisers-read-zero */
#include <stdio.h>
static int si = 7;
int gi = 9;
static long long sll = 5;
long long gll = 6;
static double sd = 2.5;
static const double scd = 3.5;
static unsigned char sc = 200;
static int h;
__attribute__((constructor)) static void ctor(void) { h = si * 3; }
int main(void) {
  printf("ctor h %d\n", h);
  printf("si %d gi %d sll %lld gll %lld sd %g scd %g sc %d\n", si, gi, sll, gll, sd, scd, sc);
  return 0; }
