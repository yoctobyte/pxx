/* SPDX-License-Identifier: 0BSD
 * A struct passed BY VALUE through a pointer declared from a FUNCTION-TYPE
 * typedef must use the same ABI as the callee's own declaration.
 *
 * `typedef void F(args); F *p;` and `typedef void (*P)(args); P p;` name the
 * same callable thing in C, and pxx registered a signature for both -- but only
 * the pointer spelling recorded WHICH record each struct parameter is
 * (ProcParamRecId). Without it the SysV classifier has no RecSize, so a
 * by-value struct was passed as though it were a pointer while the callee,
 * compiled from the real declaration, read its registers per the true layout.
 *
 * SCALARS WERE UNAFFECTED, which is exactly why this survived: an int or a
 * pointer needs no record identity, so a fixture that passed one certified the
 * broken path. The rows below therefore keep a scalar row AND struct rows, and
 * the struct rows are what can fail.
 *
 * Found on quickjs-ng: JSValue (16 bytes, INTEGER+INTEGER) reached a class
 * finalizer as a stack address with tag 70 instead of the object and -1, and
 * the engine freed a -1 pointer. quickjs is a unity build of ~85k lines; this
 * file is the 40-line version.
 *
 * Three struct classes on purpose, because SysV treats them differently and one
 * shape passing says nothing about the others: INTEGER+INTEGER, SSE+SSE, and a
 * single eightbyte. Expected values are non-default (0x1234, -1, 1.5/2.5, 77)
 * so a row cannot pass by colliding with a zeroed or unwritten slot. */
#include <stdio.h>
#include <stdint.h>

typedef union { int32_t int32; double float64; void *ptr; } U;
typedef struct { U u; int64_t tag; } V;   /* quickjs's JSValue shape */
typedef struct { double a, b; } D2;
typedef struct { long a; } S8;

static int fails = 0;
#define CHECK(c, what) do { if (!(c)) { printf("FAIL %s\n", what); fails++; } } while (0)

static void take_v (void *r, V v)  { CHECK(v.u.ptr == (void *)0x1234 && v.tag == -1, "V"); }
static void take_d2(void *r, D2 d) { CHECK(d.a == 1.5 && d.b == 2.5, "D2"); }
static void take_s8(void *r, S8 s) { CHECK(s.a == 77, "S8"); }
static void take_i (int a, int b)  { CHECK(a == 11 && b == 22, "int"); }

typedef void FV(void *, V);
typedef void FD2(void *, D2);
typedef void FS8(void *, S8);
typedef void FI(int, int);

/* quickjs's exact storage shape: the pointer lives in an array of structs. */
typedef struct { FV *fn; } Slot;
static Slot slots[4];

int main(void)
{
  FV *fv = take_v;  FD2 *fd = take_d2;  FS8 *fs = take_s8;  FI *fi = take_i;
  V v; D2 d; S8 s;
  v.u.ptr = (void *)0x1234; v.tag = -1;
  d.a = 1.5; d.b = 2.5;
  s.a = 77;

  fi(11, 22);                 /* scalar: was already correct, keeps it correct */
  fv((void *)1, v);
  fd((void *)1, d);
  fs((void *)1, s);

  /* compound literal straight into the call, as JS_MKPTR does */
  fv((void *)1, (V){ (U){ .ptr = (void *)0x1234 }, -1 });

  /* through an array-of-struct member, with and without a local */
  slots[2].fn = take_v;
  slots[2].fn((void *)1, v);
  { FV *via = slots[2].fn; via((void *)1, v); }

  if (fails == 0) printf("fntype-typedef struct ABI: 7 rows OK\n");
  return fails != 0;
}
