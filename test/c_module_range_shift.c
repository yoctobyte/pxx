/* An included .c's last `static` definition belongs to the module of its
   prototype. Token rewrites (split typedefs) moved the tokens but not the C
   module ranges, so the body fell into the main source's range, became a
   second symbol row, and the reference through `pp` stayed undefined in an
   --emit-obj object (freetype's unity type1.c, T1_Get_Track_Kerning).
   bug-c-token-edits-do-not-move-the-c-module-ranges */
#include "c_module_range_shift_mod.c"
static int (*pp)(int) = last_fn;
int main(void) { printf("%d\n", pp(14)); return 0; }
