/* A program whose ONLY crtl reference is a hand-written `printf` prototype must
   not warn about a duplicate definition. It did: the prototype pull brings in
   whichever crtl `.c` modules the TU needs, and two of them -- fcntl.c and
   unistd.c -- each have a file-scope `static int sysret`. In C those are two
   translation units and both are legal.

   The cause was an ORDERING, not a missing check. CModuleOfTok scans backward
   and takes the last range starting at or before the token, so "later in the
   array wins" -- and CPullCrtlForPrototypes marked the whole appended block as
   one module AFTER the lexer had already marked each pulled `.c` with its own
   path. The coarse range did not get refined by the finer ones, it SHADOWED
   every one of them, and the block collapsed into a single module. The range
   is now INSERTED ahead of them.

   The assertion is zero warnings AND a correct run: a fix that suppressed the
   diagnostic wholesale would pass the first half and cost the true positive
   that test/cstatic_same_module_dup.c guards. Those two files are the pair.
   bug-c-static-functions-in-different-crtl-modules-collide */
extern int printf(const char *, ...);

int main(void) { printf("prototype pull ok\n"); return 0; }
