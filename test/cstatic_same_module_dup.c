/* The TRUE positive that must survive: two same-named file-scope statics in ONE
   real translation unit. gcc REJECTS this outright ("redefinition of 'helper'");
   pxx warns and compiles, binding each call to whichever body was current when
   the call was compiled -- so fa() is 2 and fb() is 11.
 
   Kept beside test/cstatic_two_modules.c on purpose. That file proves the
   warning no longer fires on legal cross-module statics; this one proves the
   fix did not simply suppress statics, which would have cost the real
   diagnostic. bug-c-static-functions-in-different-crtl-modules-collide */
extern int printf(const char *, ...);

static int helper(int x) { return x + 1; }
int fa(void) { return helper(1); }

static int helper(int x) { return x + 10; }
int fb(void) { return helper(1); }

int main(void) { printf("%d %d\n", fa(), fb()); return 0; }
