/* The C half of the argv[0]-independence canary (see quick_canary_argv0.pas).
   Compiled with NO -I on purpose: that is what makes lib/crtl resolve through
   ExeDir (the directory of ParamStr(0)), and those resolved module paths were
   being interned into the EMITTED string pool -- so the same compiler emitted
   './compiler/../lib/crtl/src/stdio.c' into the binary when run from the repo
   and nothing when run from a copy elsewhere. 218207 vs 218095 bytes.
   bug-a-the-compilers-output-depends-on-argv0 */
#include <stdio.h>
int main(void) { printf("c argv0 canary ok %d\n", 42); return 0; }
