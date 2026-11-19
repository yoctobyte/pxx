/* Module A of the two-module static VARIABLE probe. Included, never compiled
   alone — it is an INPUT to test/cstatic_two_modules_vars_distinct.c, which is
   what the Makefile runs.

   The variable twin of cstatic_mod_a.c. `v` here and `v` in
   cstatic_var_mod_b.c are two distinct OBJECTS with internal linkage (C
   6.2.2), and they are initialised to DIFFERENT values for the same reason
   that file's functions return different values: crtl's real instance of the
   function shape has two byte-identical bodies and so cannot tell a correct
   bind from a wrong one. 1 is not 2, so a read that resolves to the wrong
   module's object is visible rather than masked.

   ma_set exists because the READ and the WRITE fail independently: sharing one
   Syms[] row makes A's read return B's value AND A's write change B's object,
   and a fix can address either alone.
   bug-c-two-same-named-file-scope-static-variables-share-one-syms-row-and-alias */

static int v = 1;

/* DIFFERENT EXTENTS on purpose. sizeof reads the SYMBOL's own metadata rather
   than any value, so it fails independently of the read and write rows -- and
   it did: with only the value path module-aware, both modules answered 24. A
   value assertion physically cannot observe that, which is why this pair is
   here and why the extents differ (3 vs 6). */
static int arr[3] = { 1, 1, 1 };

int  ma_get(void)  { return v; }
void ma_set(int x) { v = x; }
int  ma_size(void) { return (int)sizeof(arr); }
