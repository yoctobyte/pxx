/* A struct returned in REGISTERS (SysV x86-64, <= 16 bytes) is stored back at
   its own size, not at register width: the bytes past the record belong to
   the next local. csmith seed 1120027: `func_1();` discarding a 4-byte union
   wrote rax's high half over main's print_hash_value. Sizes 1..16, both
   register classes; each case has the shape that exposed it -- a 4-byte local
   declared just before the sentinel, the result discarded, the sentinel read
   right after. No shape here has padding: a register return need not carry
   padding bytes, so a byte hash over them would compare nothing defined.
   Expectations are gcc's.
   bug-c-a-struct-returned-in-registers-is-stored-at-register-width */
#include <stdio.h>
#include <string.h>

static void show(const char *n, unsigned sz, unsigned sum, int s) { printf("%-4s size %2u sum %08x sentinel %08x\n", n, sz, sum, s); }

struct C1 { char a[1]; };
static struct C1 mk_c1(int seed) { struct C1 r; unsigned char *p = (unsigned char *)&r; for (unsigned i = 0; i < sizeof r; i++) p[i] = (unsigned char)(seed + 17 * i + 1); return r; }
static unsigned sum_c1(struct C1 r) { unsigned char *p = (unsigned char *)&r; unsigned s = 0; for (unsigned i = 0; i < sizeof r; i++) s = s * 31 + p[i]; return s; }
static void d_c1(void) {
  int pad;
  int sentinel = 0x5A5A5A5A;
  mk_c1(3);
  show("c1", (unsigned)sizeof(struct C1), 0, sentinel);
}
static void k_c1(void) {
  struct C1 k = mk_c1(5);
  show("c1", (unsigned)sizeof k, sum_c1(k), 0);
}
struct C2 { char a[2]; };
static struct C2 mk_c2(int seed) { struct C2 r; unsigned char *p = (unsigned char *)&r; for (unsigned i = 0; i < sizeof r; i++) p[i] = (unsigned char)(seed + 17 * i + 1); return r; }
static unsigned sum_c2(struct C2 r) { unsigned char *p = (unsigned char *)&r; unsigned s = 0; for (unsigned i = 0; i < sizeof r; i++) s = s * 31 + p[i]; return s; }
static void d_c2(void) {
  int pad;
  int sentinel = 0x5A5A5A5A;
  mk_c2(3);
  show("c2", (unsigned)sizeof(struct C2), 0, sentinel);
}
static void k_c2(void) {
  struct C2 k = mk_c2(5);
  show("c2", (unsigned)sizeof k, sum_c2(k), 0);
}
struct C3 { char a[3]; };
static struct C3 mk_c3(int seed) { struct C3 r; unsigned char *p = (unsigned char *)&r; for (unsigned i = 0; i < sizeof r; i++) p[i] = (unsigned char)(seed + 17 * i + 1); return r; }
static unsigned sum_c3(struct C3 r) { unsigned char *p = (unsigned char *)&r; unsigned s = 0; for (unsigned i = 0; i < sizeof r; i++) s = s * 31 + p[i]; return s; }
static void d_c3(void) {
  int pad;
  int sentinel = 0x5A5A5A5A;
  mk_c3(3);
  show("c3", (unsigned)sizeof(struct C3), 0, sentinel);
}
static void k_c3(void) {
  struct C3 k = mk_c3(5);
  show("c3", (unsigned)sizeof k, sum_c3(k), 0);
}
struct I4 { unsigned a; };
static struct I4 mk_i4(int seed) { struct I4 r; unsigned char *p = (unsigned char *)&r; for (unsigned i = 0; i < sizeof r; i++) p[i] = (unsigned char)(seed + 17 * i + 1); return r; }
static unsigned sum_i4(struct I4 r) { unsigned char *p = (unsigned char *)&r; unsigned s = 0; for (unsigned i = 0; i < sizeof r; i++) s = s * 31 + p[i]; return s; }
static void d_i4(void) {
  int pad;
  int sentinel = 0x5A5A5A5A;
  mk_i4(3);
  show("i4", (unsigned)sizeof(struct I4), 0, sentinel);
}
static void k_i4(void) {
  struct I4 k = mk_i4(5);
  show("i4", (unsigned)sizeof k, sum_i4(k), 0);
}
struct C5 { char a[5]; };
static struct C5 mk_c5(int seed) { struct C5 r; unsigned char *p = (unsigned char *)&r; for (unsigned i = 0; i < sizeof r; i++) p[i] = (unsigned char)(seed + 17 * i + 1); return r; }
static unsigned sum_c5(struct C5 r) { unsigned char *p = (unsigned char *)&r; unsigned s = 0; for (unsigned i = 0; i < sizeof r; i++) s = s * 31 + p[i]; return s; }
static void d_c5(void) {
  int pad;
  int sentinel = 0x5A5A5A5A;
  mk_c5(3);
  show("c5", (unsigned)sizeof(struct C5), 0, sentinel);
}
static void k_c5(void) {
  struct C5 k = mk_c5(5);
  show("c5", (unsigned)sizeof k, sum_c5(k), 0);
}
struct C6 { char a[6]; };
static struct C6 mk_c6(int seed) { struct C6 r; unsigned char *p = (unsigned char *)&r; for (unsigned i = 0; i < sizeof r; i++) p[i] = (unsigned char)(seed + 17 * i + 1); return r; }
static unsigned sum_c6(struct C6 r) { unsigned char *p = (unsigned char *)&r; unsigned s = 0; for (unsigned i = 0; i < sizeof r; i++) s = s * 31 + p[i]; return s; }
static void d_c6(void) {
  int pad;
  int sentinel = 0x5A5A5A5A;
  mk_c6(3);
  show("c6", (unsigned)sizeof(struct C6), 0, sentinel);
}
static void k_c6(void) {
  struct C6 k = mk_c6(5);
  show("c6", (unsigned)sizeof k, sum_c6(k), 0);
}
struct C7 { char a[7]; };
static struct C7 mk_c7(int seed) { struct C7 r; unsigned char *p = (unsigned char *)&r; for (unsigned i = 0; i < sizeof r; i++) p[i] = (unsigned char)(seed + 17 * i + 1); return r; }
static unsigned sum_c7(struct C7 r) { unsigned char *p = (unsigned char *)&r; unsigned s = 0; for (unsigned i = 0; i < sizeof r; i++) s = s * 31 + p[i]; return s; }
static void d_c7(void) {
  int pad;
  int sentinel = 0x5A5A5A5A;
  mk_c7(3);
  show("c7", (unsigned)sizeof(struct C7), 0, sentinel);
}
static void k_c7(void) {
  struct C7 k = mk_c7(5);
  show("c7", (unsigned)sizeof k, sum_c7(k), 0);
}
struct L8 { long a; };
static struct L8 mk_l8(int seed) { struct L8 r; unsigned char *p = (unsigned char *)&r; for (unsigned i = 0; i < sizeof r; i++) p[i] = (unsigned char)(seed + 17 * i + 1); return r; }
static unsigned sum_l8(struct L8 r) { unsigned char *p = (unsigned char *)&r; unsigned s = 0; for (unsigned i = 0; i < sizeof r; i++) s = s * 31 + p[i]; return s; }
static void d_l8(void) {
  int pad;
  int sentinel = 0x5A5A5A5A;
  mk_l8(3);
  show("l8", (unsigned)sizeof(struct L8), 0, sentinel);
}
static void k_l8(void) {
  struct L8 k = mk_l8(5);
  show("l8", (unsigned)sizeof k, sum_l8(k), 0);
}
struct I3X { int a, b, c; };
static struct I3X mk_i3x(int seed) { struct I3X r; unsigned char *p = (unsigned char *)&r; for (unsigned i = 0; i < sizeof r; i++) p[i] = (unsigned char)(seed + 17 * i + 1); return r; }
static unsigned sum_i3x(struct I3X r) { unsigned char *p = (unsigned char *)&r; unsigned s = 0; for (unsigned i = 0; i < sizeof r; i++) s = s * 31 + p[i]; return s; }
static void d_i3x(void) {
  int pad;
  int sentinel = 0x5A5A5A5A;
  mk_i3x(3);
  show("i3x", (unsigned)sizeof(struct I3X), 0, sentinel);
}
static void k_i3x(void) {
  struct I3X k = mk_i3x(5);
  show("i3x", (unsigned)sizeof k, sum_i3x(k), 0);
}
struct C9 { char a[9]; };
static struct C9 mk_c9(int seed) { struct C9 r; unsigned char *p = (unsigned char *)&r; for (unsigned i = 0; i < sizeof r; i++) p[i] = (unsigned char)(seed + 17 * i + 1); return r; }
static unsigned sum_c9(struct C9 r) { unsigned char *p = (unsigned char *)&r; unsigned s = 0; for (unsigned i = 0; i < sizeof r; i++) s = s * 31 + p[i]; return s; }
static void d_c9(void) {
  int pad;
  int sentinel = 0x5A5A5A5A;
  mk_c9(3);
  show("c9", (unsigned)sizeof(struct C9), 0, sentinel);
}
static void k_c9(void) {
  struct C9 k = mk_c9(5);
  show("c9", (unsigned)sizeof k, sum_c9(k), 0);
}
struct C11 { char a[11]; };
static struct C11 mk_c11(int seed) { struct C11 r; unsigned char *p = (unsigned char *)&r; for (unsigned i = 0; i < sizeof r; i++) p[i] = (unsigned char)(seed + 17 * i + 1); return r; }
static unsigned sum_c11(struct C11 r) { unsigned char *p = (unsigned char *)&r; unsigned s = 0; for (unsigned i = 0; i < sizeof r; i++) s = s * 31 + p[i]; return s; }
static void d_c11(void) {
  int pad;
  int sentinel = 0x5A5A5A5A;
  mk_c11(3);
  show("c11", (unsigned)sizeof(struct C11), 0, sentinel);
}
static void k_c11(void) {
  struct C11 k = mk_c11(5);
  show("c11", (unsigned)sizeof k, sum_c11(k), 0);
}
struct IC { int a; char b[4]; };
static struct IC mk_ic(int seed) { struct IC r; unsigned char *p = (unsigned char *)&r; for (unsigned i = 0; i < sizeof r; i++) p[i] = (unsigned char)(seed + 17 * i + 1); return r; }
static unsigned sum_ic(struct IC r) { unsigned char *p = (unsigned char *)&r; unsigned s = 0; for (unsigned i = 0; i < sizeof r; i++) s = s * 31 + p[i]; return s; }
static void d_ic(void) {
  int pad;
  int sentinel = 0x5A5A5A5A;
  mk_ic(3);
  show("ic", (unsigned)sizeof(struct IC), 0, sentinel);
}
static void k_ic(void) {
  struct IC k = mk_ic(5);
  show("ic", (unsigned)sizeof k, sum_ic(k), 0);
}
struct SC { short a; char b; };
static struct SC mk_sc(int seed) { struct SC r; unsigned char *p = (unsigned char *)&r; for (unsigned i = 0; i < sizeof r; i++) p[i] = (unsigned char)(seed + 17 * i + 1); return r; }
static unsigned sum_sc(struct SC r) { unsigned char *p = (unsigned char *)&r; unsigned s = 0; for (unsigned i = 0; i < sizeof r; i++) s = s * 31 + p[i]; return s; }
static void d_sc(void) {
  int pad;
  int sentinel = 0x5A5A5A5A;
  mk_sc(3);
  show("sc", (unsigned)sizeof(struct SC), 0, sentinel);
}
static void k_sc(void) {
  struct SC k = mk_sc(5);
  show("sc", (unsigned)sizeof k, sum_sc(k), 0);
}
struct F1 { float a; };
static struct F1 mk_f1(int seed) { struct F1 r; unsigned char *p = (unsigned char *)&r; for (unsigned i = 0; i < sizeof r; i++) p[i] = (unsigned char)(seed + 17 * i + 1); return r; }
static unsigned sum_f1(struct F1 r) { unsigned char *p = (unsigned char *)&r; unsigned s = 0; for (unsigned i = 0; i < sizeof r; i++) s = s * 31 + p[i]; return s; }
static void d_f1(void) {
  int pad;
  int sentinel = 0x5A5A5A5A;
  mk_f1(3);
  show("f1", (unsigned)sizeof(struct F1), 0, sentinel);
}
static void k_f1(void) {
  struct F1 k = mk_f1(5);
  show("f1", (unsigned)sizeof k, sum_f1(k), 0);
}
struct F3 { float a, b, c; };
static struct F3 mk_f3(int seed) { struct F3 r; unsigned char *p = (unsigned char *)&r; for (unsigned i = 0; i < sizeof r; i++) p[i] = (unsigned char)(seed + 17 * i + 1); return r; }
static unsigned sum_f3(struct F3 r) { unsigned char *p = (unsigned char *)&r; unsigned s = 0; for (unsigned i = 0; i < sizeof r; i++) s = s * 31 + p[i]; return s; }
static void d_f3(void) {
  int pad;
  int sentinel = 0x5A5A5A5A;
  mk_f3(3);
  show("f3", (unsigned)sizeof(struct F3), 0, sentinel);
}
static void k_f3(void) {
  struct F3 k = mk_f3(5);
  show("f3", (unsigned)sizeof k, sum_f3(k), 0);
}
struct DFF { double a; float b, c; };
static struct DFF mk_dff(int seed) { struct DFF r; unsigned char *p = (unsigned char *)&r; for (unsigned i = 0; i < sizeof r; i++) p[i] = (unsigned char)(seed + 17 * i + 1); return r; }
static unsigned sum_dff(struct DFF r) { unsigned char *p = (unsigned char *)&r; unsigned s = 0; for (unsigned i = 0; i < sizeof r; i++) s = s * 31 + p[i]; return s; }
static void d_dff(void) {
  int pad;
  int sentinel = 0x5A5A5A5A;
  mk_dff(3);
  show("dff", (unsigned)sizeof(struct DFF), 0, sentinel);
}
static void k_dff(void) {
  struct DFF k = mk_dff(5);
  show("dff", (unsigned)sizeof k, sum_dff(k), 0);
}
struct DII { double a; int b, c; };
static struct DII mk_dii(int seed) { struct DII r; unsigned char *p = (unsigned char *)&r; for (unsigned i = 0; i < sizeof r; i++) p[i] = (unsigned char)(seed + 17 * i + 1); return r; }
static unsigned sum_dii(struct DII r) { unsigned char *p = (unsigned char *)&r; unsigned s = 0; for (unsigned i = 0; i < sizeof r; i++) s = s * 31 + p[i]; return s; }
static void d_dii(void) {
  int pad;
  int sentinel = 0x5A5A5A5A;
  mk_dii(3);
  show("dii", (unsigned)sizeof(struct DII), 0, sentinel);
}
static void k_dii(void) {
  struct DII k = mk_dii(5);
  show("dii", (unsigned)sizeof k, sum_dii(k), 0);
}
struct IID { int a, b; double c; };
static struct IID mk_iid(int seed) { struct IID r; unsigned char *p = (unsigned char *)&r; for (unsigned i = 0; i < sizeof r; i++) p[i] = (unsigned char)(seed + 17 * i + 1); return r; }
static unsigned sum_iid(struct IID r) { unsigned char *p = (unsigned char *)&r; unsigned s = 0; for (unsigned i = 0; i < sizeof r; i++) s = s * 31 + p[i]; return s; }
static void d_iid(void) {
  int pad;
  int sentinel = 0x5A5A5A5A;
  mk_iid(3);
  show("iid", (unsigned)sizeof(struct IID), 0, sentinel);
}
static void k_iid(void) {
  struct IID k = mk_iid(5);
  show("iid", (unsigned)sizeof k, sum_iid(k), 0);
}
struct C15 { char a[15]; };
static struct C15 mk_c15(int seed) { struct C15 r; unsigned char *p = (unsigned char *)&r; for (unsigned i = 0; i < sizeof r; i++) p[i] = (unsigned char)(seed + 17 * i + 1); return r; }
static unsigned sum_c15(struct C15 r) { unsigned char *p = (unsigned char *)&r; unsigned s = 0; for (unsigned i = 0; i < sizeof r; i++) s = s * 31 + p[i]; return s; }
static void d_c15(void) {
  int pad;
  int sentinel = 0x5A5A5A5A;
  mk_c15(3);
  show("c15", (unsigned)sizeof(struct C15), 0, sentinel);
}
static void k_c15(void) {
  struct C15 k = mk_c15(5);
  show("c15", (unsigned)sizeof k, sum_c15(k), 0);
}
struct L2 { long a, b; };
static struct L2 mk_l2(int seed) { struct L2 r; unsigned char *p = (unsigned char *)&r; for (unsigned i = 0; i < sizeof r; i++) p[i] = (unsigned char)(seed + 17 * i + 1); return r; }
static unsigned sum_l2(struct L2 r) { unsigned char *p = (unsigned char *)&r; unsigned s = 0; for (unsigned i = 0; i < sizeof r; i++) s = s * 31 + p[i]; return s; }
static void d_l2(void) {
  int pad;
  int sentinel = 0x5A5A5A5A;
  mk_l2(3);
  show("l2", (unsigned)sizeof(struct L2), 0, sentinel);
}
static void k_l2(void) {
  struct L2 k = mk_l2(5);
  show("l2", (unsigned)sizeof k, sum_l2(k), 0);
}
int main(void) {
  d_c1(); k_c1();
  d_c2(); k_c2();
  d_c3(); k_c3();
  d_i4(); k_i4();
  d_c5(); k_c5();
  d_c6(); k_c6();
  d_c7(); k_c7();
  d_l8(); k_l8();
  d_i3x(); k_i3x();
  d_c9(); k_c9();
  d_c11(); k_c11();
  d_ic(); k_ic();
  d_sc(); k_sc();
  d_f1(); k_f1();
  d_f3(); k_f3();
  d_dff(); k_dff();
  d_dii(); k_dii();
  d_iid(); k_iid();
  d_c15(); k_c15();
  d_l2(); k_l2();
  return 0;
}
