/* THE GCC HALF of the mixed-link gate. gcc compiles this and links it against
   a pxx-compiled c_abi_mixed_link_pxx.o. Every printed number crosses the
   boundary in one direction or the other; none of them can be produced by pxx
   agreeing with itself.
   bug-a-c-a-by-value-struct-parameter-is-passed-as-a-pointer-to-every-c-abi-callee */
#include <stdio.h>

struct P2  { int a, b; };
struct P4  { int a, b, c, d; };
struct P6  { int a, b, c, d, e, f; };
struct D2  { double x, y; };
struct MIX { int a; double y; };
struct C3  { char a, b, c; };

/* pxx callees, called from here. */
extern int    take_p2 (struct P2 p);
extern int    take_p4 (struct P4 p);
extern int    take_p6 (struct P6 p);
extern double take_d2 (struct D2 p);
extern double take_mix(struct MIX p);
extern int    take_c3 (struct C3 p);
extern int    take_late(int a, int b, int c, int d, int e, struct P2 p);

/* gcc callees, called from pxx via the relay_* wrappers below. */
int    gcc_p2 (struct P2 p)  { return p.a * 10 + p.b; }
int    gcc_p4 (struct P4 p)  { return ((p.a * 10 + p.b) * 10 + p.c) * 10 + p.d; }
int    gcc_p6 (struct P6 p)  { return p.a*1 + p.b*2 + p.c*3 + p.d*4 + p.e*5 + p.f*6; }
double gcc_d2 (struct D2 p)  { return p.x * 10.0 + p.y; }
double gcc_mix(struct MIX p) { return p.a * 100.0 + p.y; }
int    gcc_late(int a, int b, int c, int d, int e, struct P2 p)
{ return ((((a*10+b)*10+c)*10+d)*10+e) * 100 + p.a * 10 + p.b; }

/* The VARIADIC half. gcc's own `...` callees, plus the pxx variadic callees
   this file calls. A struct through `...` is a third convention and it fails
   independently of the two above -- see the long note in the pxx half. */
#include <stdarg.h>
int gcc_va_p2(int n, ...)
{ struct P2 p; va_list ap; va_start(ap,n); p = va_arg(ap, struct P2); va_end(ap);
  return p.a * 10 + p.b; }
int gcc_va_p4(int n, ...)
{ struct P4 p; va_list ap; va_start(ap,n); p = va_arg(ap, struct P4); va_end(ap);
  return ((p.a * 10 + p.b) * 10 + p.c) * 10 + p.d; }
int gcc_va_p6(int n, ...)
{ struct P6 p; va_list ap; va_start(ap,n); p = va_arg(ap, struct P6); va_end(ap);
  return p.a*1 + p.b*2 + p.c*3 + p.d*4 + p.e*5 + p.f*6; }
double gcc_va_d2(int n, ...)
{ struct D2 p; va_list ap; va_start(ap,n); p = va_arg(ap, struct D2); va_end(ap);
  return p.x * 10.0 + p.y; }
double gcc_va_mix(int n, ...)
{ struct MIX p; va_list ap; va_start(ap,n); p = va_arg(ap, struct MIX); va_end(ap);
  return p.a * 100.0 + p.y; }
int gcc_va_c3(int n, ...)
{ struct C3 p; va_list ap; va_start(ap,n); p = va_arg(ap, struct C3); va_end(ap);
  return p.a * 100 + p.b * 10 + p.c; }
int gcc_va_full(int a, int b, int c, int d, int e, ...)
{ struct P4 p; va_list ap; va_start(ap,e); p = va_arg(ap, struct P4); va_end(ap);
  return ((((a*10+b)*10+c)*10+d)*10+e) * 10000
         + ((p.a * 10 + p.b) * 10 + p.c) * 10 + p.d; }

extern int    va_take_p2 (int n, ...);
extern int    va_take_p4 (int n, ...);
extern int    va_take_p6 (int n, ...);
extern double va_take_d2 (int n, ...);
extern double va_take_mix(int n, ...);
extern int    va_take_c3 (int n, ...);
extern int    va_take_full(int a, int b, int c, int d, int e, ...);
extern int    va_relay_p2 (void);
extern int    va_relay_p4 (void);
extern int    va_relay_p6 (void);
extern double va_relay_d2 (void);
extern double va_relay_mix(void);
extern int    va_relay_c3 (void);
extern int    va_relay_full(void);

extern int    relay_p2 (int a, int b);
extern int    relay_p4 (void);
extern int    relay_p6 (void);
extern double relay_d2 (void);
extern double relay_mix(void);
extern int    relay_late(void);
extern int    relay_p2_ind(void);
extern double relay_mix_ind(void);

int main(void)
{
  struct P2  p2  = {3, 7};
  struct P4  p4  = {1, 2, 3, 4};
  struct P6  p6  = {1, 2, 3, 4, 5, 6};
  struct D2  d2  = {1.5, 2.5};
  struct MIX mx  = {7, 0.25};
  struct C3  c3  = {1, 2, 3};

  printf("take_p2 %d\n",    take_p2(p2));
  printf("take_p4 %d\n",    take_p4(p4));
  printf("take_p6 %d\n",    take_p6(p6));
  printf("take_d2 %.2f\n",  take_d2(d2));
  printf("take_mix %.2f\n", take_mix(mx));
  printf("take_c3 %d\n",    take_c3(c3));
  printf("take_late %d\n",  take_late(1,2,3,4,5,p2));

  printf("relay_p2 %d\n",    relay_p2(3, 7));
  printf("relay_p4 %d\n",    relay_p4());
  printf("relay_p6 %d\n",    relay_p6());
  printf("relay_d2 %.2f\n",  relay_d2());
  printf("relay_mix %.2f\n", relay_mix());
  printf("relay_late %d\n",  relay_late());
  printf("relay_p2_ind %d\n",    relay_p2_ind());
  printf("relay_mix_ind %.2f\n", relay_mix_ind());

  printf("va_take_p2 %d\n",    va_take_p2(0, p2));
  printf("va_take_p4 %d\n",    va_take_p4(0, p4));
  printf("va_take_p6 %d\n",    va_take_p6(0, p6));
  printf("va_take_d2 %.2f\n",  va_take_d2(0, d2));
  printf("va_take_mix %.2f\n", va_take_mix(0, mx));
  printf("va_take_c3 %d\n",    va_take_c3(0, c3));
  printf("va_take_full %d\n",  va_take_full(1,2,3,4,5, p4));
  printf("va_relay_p2 %d\n",    va_relay_p2());
  printf("va_relay_p4 %d\n",    va_relay_p4());
  printf("va_relay_p6 %d\n",    va_relay_p6());
  printf("va_relay_d2 %.2f\n",  va_relay_d2());
  printf("va_relay_mix %.2f\n", va_relay_mix());
  printf("va_relay_c3 %d\n",    va_relay_c3());
  printf("va_relay_full %d\n",  va_relay_full());
  return 0;
}
