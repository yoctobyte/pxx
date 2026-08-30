/* A C program's own functions must NOT be marshalled as C-ABI calls.

   bug-a-a-c-mode-function-took-the-cdecl-call-path-on-aarch64-and-arm32

   Every C function is marked ProcCdecl by the C frontend, and a C-DEFINED
   function is not ProcExternal. When the aarch64/arm32 direct-call sites learned
   to route ProcCdecl procs onto the C-ABI marshalling path (for bodied Pascal
   `cdecl` procs, which do have a matching prologue), that expression also
   dragged in every function of every C program -- where cparser's own prologue
   spill is POSITIONAL on those two targets, not AAPCS.

   Two symptoms, one cause, both asserted here:
     nine()  - more than 8 parameters. The C-ABI path refuses >8 on aarch64 and
               refuses a >16-byte block on arm32, limits the internal path does
               not have. Broke the lua cross build with
               "external call with more than 8 parameters not supported".
     mix()   - float parameters within every limit. Marshalled AAPCS, received
               positionally: garbage, not a refusal. This is the half that broke
               four C-conformance shards with an output mismatch.

   x86-64 could not catch either, because cparser's x86-64 prologue spill really
   is SysV, so caller and callee agreed there. A regression test for a
   convention mismatch has to run on the targets whose two halves disagree. */
#include <stdio.h>

int nine(int a, int b, int c, int d, int e, int f, int g, int h, int i)
{
  return a + b + c + d + e + f + g + h + i;
}

double mix(int a, double b, int c, double d)
{
  return a + b + c + d;
}

int main(void)
{
  int n = nine(1, 2, 3, 4, 5, 6, 7, 8, 9);      /* want 45 */
  double m = mix(1, 2.0, 3, 4.0);               /* want 10 */
  if (n != 45)  { printf("FAIL nine=%d want 45\n", n); return 1; }
  if (m != 10.0){ printf("FAIL mix=%f want 10\n", m); return 1; }
  printf("CDECL-CMODE OK\n");
  return 0;
}
