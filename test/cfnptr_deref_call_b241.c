/* SPDX-License-Identifier: Zlib */
/* Regression b241 (bug-c-call-through-deref-of-fnptr-pointer, bare-identifier
   form): `ft *pf; (*pf)(args)` — a call through the deref of a POINTER-to-
   function-pointer VARIABLE. cparser's CNodeProcSig greedily stripped every
   AN_DEREF, so `*pf` reached AN_IDENT where SymProcSig[pf] is -1 (pf is a
   pointer, not a fn-pointer) → the call was dropped, yielding the fn's own code
   bytes as data. Fix: thread the pointee sig (CTypePtrElemProcSig) into the
   SymElemProcSig channel at the local/param/global declarator sites (same
   channel as `pf[0](args)`, since `*pf` == `pf[0]`), and keep one deref as the
   callee. Exit 42 = all forms call correctly. */

typedef long (*ft)(long);
static long add100(long x) { return x + 100; }
static long mul3(long x)   { return x * 3; }

static ft gF = add100;
static ft *gpf = &gF;                 /* global ptr-to-fnptr */

static long via_param(ft *pf) { return (*pf)(5); }   /* param ptr-to-fnptr */

int main(void) {
  ft lf = mul3;
  ft *lpf = &lf;                      /* local ptr-to-fnptr */

  if ((*lpf)(7)      != 21)  return 1; /* local:  mul3(7) */
  if (via_param(&gF) != 105) return 2; /* param:  add100(5) */
  if ((*gpf)(5)      != 105) return 3; /* global: add100(5) */

  /* reassign through the pointer, re-call */
  lf = add100;
  if ((*lpf)(1)      != 101) return 4;

  /* `pf[0](args)` must still work (the shared channel) */
  if (lpf[0](2)      != 102) return 5;

  return 42;
}
