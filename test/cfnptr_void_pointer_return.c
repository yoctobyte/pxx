/* A `void *`-returning callback must hand back all 64 bits of its pointer.

   bug-c-a-void-pointer-returning-callback-has-a-32-bit-signed-return-type

   `void *(*)(...)` had a SIGNED 4-BYTE return type in its call signature.
   ParseCDeclType sets Result := tyInteger as a placeholder for a `void` base
   whose own comment says "pointer suffix overrides below" -- and the star loop
   does override it to tyPointer -- but the fn-pointer branch then re-applied
   the placeholder, overriding the override.

   Latent for as long as it existed, because nothing read the type: the value
   travelled through RAX untouched and was right by accident. It became fatal
   the moment the indirect cdecl arm learned to widen a 32-bit signed return
   (e5a21152b, correct in itself and still correct): it read that type, emitted
   `cdqe`, and truncated the pointer. lua's own allocator callback is exactly
   this shape, so lua_newstate segfaulted on the block it had just been handed
   -- 0x71a3aa200008 came back as 0xffffffffaa200008 -- and six lua programs
   produced no output at all.

   THE SUBJECT MUST CONTAIN AN ADDRESS ABOVE 4GB OR IT PROVES NOTHING. My first
   version of this test used a `static char buf[8]`, which lives below 4GB, so
   the truncated value EQUALLED the true one and every row said ok on a compiler
   I already knew was broken. `malloc` is used deliberately, and the fitness of
   the subject is asserted rather than assumed: if the heap comes back below
   4GB the test reports UNFIT and fails, instead of passing vacuously.

   THE int* ROW IS THE NEGATIVE CONTROL. Only the `void` base reached the
   defect, so a pointer-returning callback with any other base type was always
   correct; a version of this test with only the void* row would pass on a
   compiler that had merely stopped emitting cdqe at all. Exit 42 on success. */
#include <stdio.h>
#include <stdlib.h>

typedef void *(*vfn)(void *p);
typedef int  *(*ifn)(void *p);
typedef void  (*nfn)(void *p);   /* genuinely void: must KEEP the placeholder */

static void *identity_v(void *p) { return p; }
static int  *identity_i(void *p) { return (int *)p; }
static int   sawVoidCall = 0;
static void  identity_n(void *p) { (void)p; sawVoidCall = 1; }

int main(void) {
  void *want = malloc(64);
  vfn a = identity_v;
  ifn b = identity_i;
  nfn c = identity_n;
  void *gotV;
  int  *gotI;

  if (want == NULL) { printf("UNFIT: malloc failed\n"); return 1; }
  if (((unsigned long)want >> 32) == 0UL) {
    /* Not a pass. A 32-bit truncation is invisible against a 32-bit address,
       so this subject cannot contain the defect and must not report on it. */
    printf("UNFIT: heap address %p is below 4GB, truncation would be invisible\n", want);
    return 2;
  }

  gotV = a(want);
  gotI = b(want);
  c(want);

  if (gotV != want) {
    printf("FAIL: void* callback returned %p, want %p\n", gotV, want);
    return 3;
  }
  if ((void *)gotI != want) {
    printf("FAIL: int* callback returned %p, want %p\n", (void *)gotI, want);
    return 4;
  }
  if (!sawVoidCall) {
    printf("FAIL: the void-returning callback did not run\n");
    return 5;
  }
  printf("VOID PTR CALLBACK OK\n");
  return 42;
}
